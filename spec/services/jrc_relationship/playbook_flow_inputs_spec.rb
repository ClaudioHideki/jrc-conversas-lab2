require 'rails_helper'

RSpec.describe JrcRelationship::PlaybookFlowInput do
  include_context 'with a published relationship Flow'

  context 'with the published native Flow fixture' do
    let(:input_message) { client_reply(content: 'Quero ATENDIMENTO do cliente') }
    let(:flow) { super().tap { |row| row.update!(settings: row.settings.merge('keyword' => 'atendimento')) } }
    let(:step) { super().merge('message_id' => input_message.id) }
    let(:node_definitions) do
      [['start', {}], ['condition', { 'field' => 'message', 'operator' => 'contains', 'value' => 'ATENDIMENTO' }],
       ['delay', { 'seconds' => 5 }], ['note', { 'text' => 'Reviewed keyword route' }], ['end', {}]]
    end

    def graph
      value = super
      value['edges'].find { |edge| edge['source'] == 'node1' }['port'] = 'yes'
      value['edges'] << { 'id' => 'negative', 'source' => 'node1', 'port' => 'no', 'target' => 'node4' }
      value
    end

    it 'binds the explicit incoming message and uses it in the native condition and simulator' do
      expect(review).to include('reason' => nil)
      expect(review.dig('simulation', 'trace').map { |item| item['node_id'] }).to include('node2', 'node3')
      expect(review.to_json).not_to include(input_message.content, 'variables', 'sender_id')
      run = start_continuation
      expect(run).to have_attributes(status: 'delayed', node_id: 'node2')
      expect(run.variables.fetch('message')).to eq(input_message.content)
      wake_continuation(run)
      expect(run.status).to eq('completed')
      expect(flow_messages(run).map(&:content)).to eq(['Reviewed keyword route'])
    end

    it 'does not select a latest message when a keyword flow has no explicit published input' do
      input_message
      missing = step.except('message_id')
      preview = adapter.preview(assignment: assignment, step: missing, source_key: source_key)
      expect(preview.fetch('dependencies')).to include('native_message_keyword_input_required')
      expect(JrcFlowRun.where(flow: flow)).not_to exist
    end

    it 'treats a retry of the bound original incoming message as consumed rather than interrupting the native delay' do
      run = start_continuation
      steps = run.steps
      JrcFlows::Runner.new(run).perform(message: input_message)
      expect(run.reload).to have_attributes(status: 'delayed', last_message_id: input_message.id, steps: steps)
      expect(flow_messages(run)).to be_empty
    end

    it 'blocks a keyword mismatch without producing a native run' do
      input_message.update!(content: 'Palavra diferente')
      expect(review.fetch('dependencies')).to include('playbook_flow_keyword_not_matched')
      expect(start_continuation).to include('state' => 'blocked', 'reason' => 'playbook_flow_keyword_not_matched')
      expect(JrcFlowRun.where(flow: flow)).not_to exist
    end

    it 'invalidates a changed original input during a wait rather than using a replacement message' do
      run = start_continuation
      input_message.update!(content: 'ATENDIMENTO com conteúdo editado')
      client_reply(content: 'Quero ATENDIMENTO do cliente')
      wake_continuation(run)
      expect(run.status).to eq('paused')
      expect(flow_messages(run)).to be_empty
    end

    it 'rejects a foreign, private, outgoing or unrelated native message before preview' do
      foreign = create(:message, account: sd_foreign_account, message_type: :incoming)
      outgoing = create(:message, account: sd_account, conversation: conversation, inbox: inbox, message_type: :outgoing)
      private_message = client_reply.tap { |row| row.update!(private: true) }
      other = create(:conversation, account: sd_account, contact: sd_contact, inbox: inbox)
      unrelated = create(:message, account: sd_account, conversation: other, inbox: inbox, sender: sd_contact, message_type: :incoming)
      [[foreign, ActiveRecord::RecordNotFound], [outgoing, Pundit::NotAuthorizedError],
       [private_message, Pundit::NotAuthorizedError], [unrelated, ActiveRecord::RecordNotFound]].each do |row, error_class|
        expect { adapter.preview(assignment: assignment, step: step.merge('message_id' => row.id), source_key: source_key) }
          .to raise_error(error_class)
      end
      expect(JrcFlowRun.where(flow: flow)).not_to exist
    end

    it 'rejects a versioned playbook whose incoming input does not belong to its explicit native identity' do
      unrelated = create(:message, account: sd_account, message_type: :incoming)
      value = JrcRelationship::Playbook.new(account: sd_account, name: 'Invalid explicit input', trigger_kind: 'health',
                                            steps: [step.merge('message_id' => unrelated.id)])
      expect(value).not_to be_valid
      expect(value.errors[:steps]).to include('flow message must be the explicitly selected native incoming contact message')
    end

    context 'with a published native calendar' do
      let(:flow) do
        super().tap do |row|
          row.update!(settings: row.settings.merge('business_hours' => true, 'timezone' => 'UTC', 'opens_at' => '08:00',
                                                   'closes_at' => '18:00', 'days' => [4]))
        end
      end

      it 'admits inside the exact native calendar and uses its configured timezone' do
        travel_to(Time.utc(2026, 10, 8, 10, 0), with_usec: true)
        expect(review).to include('reason' => nil)
        run = start_continuation
        expect(run.status).to eq('delayed')
        wake_continuation(run)
        expect(run.status).to eq('completed')
      end

      it 'blocks outside the calendar before any native run or message effect' do
        travel_to(Time.utc(2026, 10, 8, 18, 0), with_usec: true) do
          expect(review.fetch('dependencies')).to include('playbook_flow_outside_calendar')
          expect(start_continuation).to include('state' => 'blocked', 'reason' => 'playbook_flow_outside_calendar')
          expect(JrcFlowRun.where(flow: flow)).not_to exist
        end
      end

      it 'rechecks the native calendar after a persisted wait without extending approval' do
        run = travel_to(Time.utc(2026, 10, 8, 17, 59, 58), with_usec: true) { start_continuation }
        wake_continuation(run)
        expect(run).to have_attributes(status: 'paused', error: 'playbook_flow_authorization_blocked')
        expect(flow_messages(run)).to be_empty
      end
    end
  end
end
