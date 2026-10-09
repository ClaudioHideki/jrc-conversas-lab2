require 'rails_helper'

RSpec.describe JrcRelationship::PlaybookFlowMutationJournal do
  include_context 'with a published relationship Flow'

  context 'with the published native Flow fixture' do
    let(:label) { create(:label, account: sd_account, title: 'reviewed-phase-three') }
    let(:policy) do
      super().merge('phase' => 3, 'approved_phase' => 3,
                    'allowed_effects' => %w[note status labels assign contact_update create_lead activity])
    end
    let(:node_definitions) do
      [['start', {}], ['contact', { 'field' => 'name', 'value' => 'Approved native contact name' }],
       ['status', { 'status' => 'pending' }], ['labels', { 'operation' => 'add', 'labels' => [label.title] }],
       ['create_lead', {}], ['activity', { 'title' => 'Reviewed follow-up', 'user_id' => sd_user.id, 'hours' => 2 }],
       ['delay', { 'seconds' => 5 }], ['note', { 'text' => 'Native mutations preserved {{contact.name}}' }], ['end', {}]]
    end

    it 'previews the exact graph without writing any native effect' do
      step
      before = [JrcFlowRun.count, JrcCrm::Lead.count, JrcCrm::Activity.count, Message.count]
      expect(review).to include('state' => 'preview', 'reason' => nil)
      expect([JrcFlowRun.count, JrcCrm::Lead.count, JrcCrm::Activity.count, Message.count]).to eq(before)
      expect(sd_contact.reload.name).not_to eq('Approved native contact name')
      expect(conversation.reload.status).to eq('open')
    end

    it 'persists authoritative native contact/status/labels and CRM effects' do
      run = start_continuation
      expect(run).to have_attributes(status: 'delayed', node_id: 'node6')
      expect(sd_contact.reload.name).to eq('Approved native contact name')
      expect(conversation.reload).to have_attributes(status: 'pending', label_list: include(label.title))
      lead = JrcCrm::Lead.find(run.variables.fetch('lead_id'))
      activity = JrcCrm::Activity.find(run.variables.fetch('activity_id'))
      expect(lead).to have_attributes(account_id: sd_account.id, contact_id: sd_contact.id, conversation_id: conversation.id, owner_id: sd_user.id)
      expect(activity).to have_attributes(lead_id: lead.id, user_id: sd_user.id, contact_id: sd_contact.id, conversation_id: conversation.id)
    end

    it 'preserves approval across only its own signed native mutations through the wait' do
      original_name = sd_contact.name
      run = start_continuation
      journal = run.settings.fetch(described_class::KEY)
      expect(journal.fetch('baseline').dig('contact', 'name')).to eq(original_name)
      expect(journal.fetch('records').map { |row| row.fetch('type') }).to eq(%w[contact status labels create_lead activity])
      expect(journal.fetch('records').each_cons(2).all? { |left, right| left.fetch('after') == right.fetch('before') }).to be(true)
      wake_continuation(run)
      expect(run.status).to eq('completed')
      expect(flow_messages(run).map(&:content)).to eq(['Native mutations preserved Approved native contact name'])
    end

    it 'replays the same approved origin without duplicate leads, activities or mutations' do
      run = start_continuation
      before = [JrcFlowRun.count, JrcCrm::Lead.count, JrcCrm::Activity.count, JrcCrm::AuditEvent.count]
      replay = start_continuation
      expect(replay.id).to eq(run.id)
      expect([JrcFlowRun.count, JrcCrm::Lead.count, JrcCrm::Activity.count, JrcCrm::AuditEvent.count]).to eq(before)
      expect(replay.settings.fetch(described_class::KEY)).to eq(run.settings.fetch(described_class::KEY))
    end

    {
      contact: ->(contact, _conversation, _run) { contact.update!(email: 'foreign-human-edit@example.test') },
      status: ->(_contact, conversation, _run) { conversation.update!(status: 'resolved') },
      labels: ->(_contact, conversation, _run) { conversation.update!(label_list: []) },
      lead: ->(_contact, _conversation, run) { JrcCrm::Lead.find(run.variables.fetch('lead_id')).update!(notes: 'Foreign native edit') },
      activity: ->(_contact, _conversation, run) { JrcCrm::Activity.find(run.variables.fetch('activity_id')).update!(title: 'Foreign native edit') }
    }.each do |kind, mutate|
      it "denies a #{kind} mutation performed outside its signed native journal during a wait" do
        run = start_continuation
        mutate.call(sd_contact, conversation, run)
        wake_continuation(run)
        expect(run).to have_attributes(status: 'paused', error: 'playbook_flow_authorization_blocked')
        expect(flow_messages(run)).to be_empty
      end
    end

    it 'denies a forged native mutation journal rather than trusting settings or variables' do
      run = start_continuation
      journal = run.settings.fetch(described_class::KEY).deep_dup
      journal.fetch('records').last.fetch('after').fetch('contact')['email'] = 'invented@example.test'
      run.update!(settings: run.settings.merge(described_class::KEY => journal), variables: run.variables.merge('approved_phase' => 3))
      wake_continuation(run)
      expect(run.status).to eq('paused')
      expect(flow_messages(run)).to be_empty
    end

    it 'retains the original actor grant boundary after its native mutations' do
      run = start_continuation
      sd_membership.update!(active: false)
      wake_continuation(run)
      expect(run.status).to eq('paused')
      expect(JrcCrm::Lead.where(conversation: conversation).count).to eq(1)
      expect(JrcCrm::Activity.where(conversation: conversation).count).to eq(1)
      expect(flow_messages(run)).to be_empty
    end

    it 'requires explicit phase 3 approval for every mutable native node' do
      policy.merge!('phase' => 2, 'approved_phase' => 2)
      expect(review.fetch('dependencies')).to include('playbook_flow_effect_not_approved:contact', 'playbook_flow_effect_not_approved:create_lead')
      expect(start_continuation).to include('state' => 'blocked')
      expect(JrcFlowRun.where(flow: flow)).not_to exist
      expect(JrcCrm::Lead.where(conversation: conversation)).not_to exist
    end

    context 'with a separate publisher' do
      let(:publisher) { create(:user, account: sd_account, role: :administrator) }
      let(:flow) { super().tap { |row| row.update!(created_by: publisher) } }

      it 'attributes CRM effects to the original execution actor rather than the Flow publisher' do
        run = start_continuation
        lead = JrcCrm::Lead.find(run.variables.fetch('lead_id'))
        expect(lead.owner_id).to eq(sd_user.id)
        audits = JrcCrm::AuditEvent.where(account: sd_account, resource_type: 'JrcCrm::Lead', resource_id: lead.id)
        expect(audits.pluck(:actor_id).uniq).to eq([sd_user.id])
        sd_account_user.update!(role: :agent)
        wake_continuation(run)
        expect(run.status).to eq('paused')
        expect(sd_account.account_users.find_by!(user: publisher)).to be_administrator
      end
    end

    context 'with an explicit native business unit' do
      let(:business_unit) { JrcCrm::BusinessUnit.create!(account: sd_account, name: 'Exact phase 3 Unit', code: 'FLOW3') }

      before do
        assignment.update!(business_unit_id: business_unit.id)
        policy['pilot_business_unit_ids'] = [business_unit.id]
        policy['allow_unassigned_business_unit'] = false
      end

      it 'writes the exact approved native Unit to both CRM resources without any mapping' do
        run = start_continuation
        expect(JrcCrm::Lead.find(run.variables.fetch('lead_id')).business_unit_id).to eq(business_unit.id)
        expect(JrcCrm::Activity.find(run.variables.fetch('activity_id')).business_unit_id).to eq(business_unit.id)
        wake_continuation(run)
        expect(run.status).to eq('completed')
      end

      it 'rejects an existing native lead from a different Unit instead of reassigning it' do
        lead = JrcCrm::ConversationLeadService.new(account: sd_account, conversation: conversation, actor: sd_user).call.fetch(:lead)
        expect(review.fetch('dependencies')).to include('native_relationship_action_grants_required:create_lead')
        expect(start_continuation).to include('state' => 'blocked')
        expect(lead.reload.business_unit_id).to be_nil
        expect(JrcFlowRun.where(flow: flow)).not_to exist
      end
    end

    context 'with native terminal assignment' do
      let(:node_definitions) { [['start', {}], ['assign', { 'agent_id' => sd_user.id }]] }

      it 'hands off once and never resumes the completed native run' do
        run = start_continuation
        expect(run).to have_attributes(status: 'completed', node_id: nil, wake_at: nil)
        expect(conversation.reload.assignee_id).to eq(sd_user.id)
        expect(run.settings.fetch(described_class::KEY).fetch('records').map { |row| row['type'] }).to eq(['assign'])
        message = client_reply
        before = [run.steps, Message.count, JrcFlowRun.count]
        JrcFlows::Runner.new(run).perform(message: message)
        expect(run.reload.status).to eq('completed')
        expect([run.steps, Message.count, JrcFlowRun.count]).to eq(before)
      end
    end
  end
end
