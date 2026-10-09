require 'rails_helper'

RSpec.describe JrcRelationship::PlaybookFlow do
  include_context 'with a published relationship Flow'

  context 'with approved native delivery and terminal effects' do
    let(:policy) { super().merge('phase' => 3, 'approved_phase' => 3, 'allowed_effects' => %w[note media webhook move_deal nico]) }

    before do
      allow(Resolv).to receive(:getaddresses).and_call_original
      allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])
    end

    context 'with an approved media node' do
      let(:node_definitions) do
        [['start', {}], ['media', { 'url' => 'https://example.com/reviewed.png', 'text' => 'Approved attachment' }],
         ['delay', { 'seconds' => 5 }], ['note', { 'text' => 'After approved media' }], ['end', {}]]
      end
      let(:media_request) do
        stub_request(:get, 'https://example.com/reviewed.png').to_return(
          status: 200, body: File.binread(Rails.root.join('spec/assets/avatar.png')), headers: { 'Content-Type' => 'image/png' }
        )
      end

      it 'does not fetch a resource or write a message during the existing preview' do
        media_request
        before = Message.count
        expect(review).to include('state' => 'preview', 'reason' => nil)
        expect(Message.count).to eq(before)
        expect(media_request).not_to have_been_requested
      end

      it 'persists one native attachment and its immutable receipt, then replays without a second fetch' do
        media_request
        run = start_continuation
        expect(run.status).to eq('delayed')
        message = flow_messages(run).fetch(0)
        expect(message).to have_attributes(content: 'Approved attachment', account_id: sd_account.id, conversation_id: conversation.id)
        expect(message.attachments.count).to eq(1)
        blob = message.attachments.first.file.blob
        expect(blob.content_type).to eq('image/png')
        expect(blob.download).to eq(File.binread(Rails.root.join('spec/assets/avatar.png')))
        expect(run.settings.dig(JrcRelationship::PlaybookFlowContinuation::JOURNAL_KEY, 'records', 'node1', 'attachment_digest')).to match(/\A[0-9a-f]{64}\z/)
        expect(start_continuation.id).to eq(run.id)
        expect(media_request).to have_been_requested.once
        expect(flow_messages(run).length).to eq(1)
      end

      it 'blocks delivery when the original operator grant is revoked' do
        media_request
        run = start_continuation
        message = flow_messages(run).fetch(0)
        sd_membership.update!(active: false)
        attempts = []
        JrcFlows::Delivery.new(message).perform { attempts << :provider }
        expect(attempts).to be_empty
        expect(message.reload.content_attributes['jrc_flow_delivery']).to eq('cancelled')
      end

      it 'rejects a replaced blob and cannot continue to the next approved node' do
        media_request
        run = start_continuation
        attachment = flow_messages(run).fetch(0).attachments.first
        attachment.file.attach(io: StringIO.new('foreign blob'), filename: 'foreign.txt', content_type: 'text/plain')
        wake_continuation(run)
        expect(run.status).to eq('paused')
        expect(flow_messages(run).length).to eq(1)
      end

      it 'keeps unapproved media OFF and rejects a private-network bypass' do
        policy['allowed_effects'] = ['note']
        expect(review['dependencies']).to include('native_relationship_action_grants_required:media')
        expect(JrcFlowRun.count).to eq(0)
      end

      it 'requires public SafeFetch even when a deployment has private fetch enabled' do
        with_modified_env(SAFE_FETCH_ALLOW_PRIVATE_NETWORK: 'true') do
          expect(review['dependencies']).to include('native_relationship_action_grants_required:media')
        end
        expect(JrcFlowRun.count).to eq(0)
      end
    end

    context 'with an explicit deal already linked to this conversation' do
      let(:pipeline) { create(:jrc_crm_pipeline, account: sd_account) }
      let(:initial_stage) { create(:jrc_crm_stage, account: sd_account, pipeline: pipeline) }
      let(:target_stage) { create(:jrc_crm_stage, account: sd_account, pipeline: pipeline) }
      let(:native_lead) do
        create(:jrc_crm_lead, account: sd_account, owner: sd_user, contact: sd_contact, conversation: conversation,
                              business_unit_id: assignment.business_unit_id, idempotency_key: "conversation:#{conversation.id}")
      end
      let(:deal) do
        create(:jrc_crm_deal, account: sd_account, owner: sd_user, pipeline: pipeline, stage: initial_stage,
                              contact: sd_contact, lead: native_lead).tap { |row| row.link_conversation!(conversation, sd_user) }
      end
      let(:node_definitions) do
        [['start', {}], ['move_deal', { 'deal_id' => deal.id, 'stage_id' => target_stage.id }],
         ['delay', { 'seconds' => 5 }], ['note', { 'text' => 'After native deal move' }], ['end', {}]]
      end

      it 'moves only the explicit native deal with the original actor and signed before/after receipt' do
        expect(review['reason']).to be_nil
        run = start_continuation
        expect(run.status).to eq('delayed')
        expect(deal.reload.stage_id).to eq(target_stage.id)
        record = run.settings.fetch(JrcRelationship::PlaybookFlowMutationJournal::KEY).fetch('records').fetch(0)
        expect(record.dig('target_before', 'attributes', 'stage_id')).to eq(initial_stage.id)
        expect(record.fetch('after').fetch('resources').find { |row| row['kind'] == 'deal' }.dig('attributes', 'stage_id')).to eq(target_stage.id)
        expect(deal.audit_events.last.actor_id).to eq(sd_user.id)
        expect(start_continuation.id).to eq(run.id)
        expect(deal.audit_events.where(event_type: 'deal_stage_changed').count).to eq(1)
      end

      it 'denies a same-customer deal lacking the exact native conversation link' do
        step
        deal.deal_conversations.destroy_all
        expect(review['dependencies']).to include('native_relationship_action_grants_required:move_deal')
        expect(deal.reload.stage_id).to eq(initial_stage.id)
      end

      it 'denies an external deal mutation while waiting before executing any downstream effect' do
        run = start_continuation
        deal.reload.update!(title: 'Human changed deal')
        wake_continuation(run)
        expect(run.status).to eq('paused')
        expect(flow_messages(run)).to be_empty
      end

      it 'never infers a deal target from a contact or an arbitrary first result' do
        node_definitions.fetch(1).fetch(1).delete('deal_id')
        expect(review['dependencies']).to include('native_relationship_action_grants_required:move_deal')
        expect(JrcFlowRun.count).to eq(0)
      end
    end

    context 'with a native terminal NICO handoff' do
      let(:node_definitions) do
        [['start', {}], ['nico', { 'objective' => 'Reviewed customer follow-up', 'hours' => 2, 'allowed_actions' => [] }]]
      end

      around { |example| with_modified_env(NICO_MODE: 'provider') { example.run } }
      before do
        sd_account.update!(custom_attributes: sd_account.custom_attributes.merge('nico_enabled' => true, 'nico_customer_delegation_enabled' => true))
        JrcAi::Provider.create!(account: sd_account, name: 'Synthetic account provider', provider_type: 'openai', default_model: 'test-model',
                               api_key: 'test-native-flow-only-key', active: true, default_provider: true)
      end

      it 'hands off terminally through the existing delegation and cannot resume its own Flow afterward' do
        expect(review['reason']).to be_nil
        run = start_continuation
        expect(run.status).to eq('completed')
        delegation = JrcNico::Delegation.find(run.variables.fetch('delegation_id'))
        expect(delegation).to have_attributes(account_id: sd_account.id, conversation_id: conversation.id, user_id: sd_user.id,
                                             status: 'active', allowed_actions: [], objective: 'Reviewed customer follow-up')
        expect(conversation.reload).to have_attributes(status: 'pending', assignee_agent_bot_id: delegation.agent_bot_id)
        expect(JrcFlowRun.live.where(conversation: conversation)).to be_empty
        JrcFlows::Runner.new(run).perform(message: client_reply)
        expect(run.reload.status).to eq('completed')
        expect(start_continuation.id).to eq(run.id)
        expect(JrcNico::Delegation.where(conversation: conversation).count).to eq(1)
      end

      it 'blocks admission if this account has no configured provider, without borrowing a global or another account key' do
        sd_account.jrc_ai_providers.destroy_all
        expect(review['dependencies']).to include('native_relationship_action_grants_required:nico')
        expect(JrcNico::Delegation.count).to eq(0)
      end
    end
  end
end
