require 'rails_helper'

RSpec.describe AutoAssignment::IncomingMessageRequest do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: true) }
  let(:policy) { create(:assignment_policy, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:historical) do
    create(:conversation, account: account, inbox: inbox).tap { |row| row.update_columns(auto_assignment_requested_at: nil) }
  end
  let(:untouched) do
    create(:conversation, account: account, inbox: inbox).tap { |row| row.update_columns(auto_assignment_requested_at: nil) }
  end

  before do
    account.enable_features!('assignment_v2')
    create(:inbox_assignment_policy, inbox: inbox, assignment_policy: policy)
    create(:inbox_member, inbox: inbox, user: agent)
    OnlineStatusTracker.update_presence(account.id, 'User', agent.id)
  end

  it 'requests only the historical conversation receiving a new public incoming message' do
    untouched
    create(:message, account: account, inbox: inbox, conversation: historical, sender: historical.contact, message_type: :incoming)

    expect(historical.reload.auto_assignment_requested_at).to be_present
    expect(untouched.reload.auto_assignment_requested_at).to be_nil
    expect(AutoAssignment::AssignmentService.new(inbox: inbox).perform_bulk_assignment).to eq(1)
    expect(historical.reload.assignee_id).to eq(agent.id)
    expect(untouched.reload.assignee_id).to be_nil
  end

  it 'does not request assignment from private, outgoing or activity messages' do
    create(:message, account: account, inbox: inbox, conversation: historical, sender: historical.contact, message_type: :incoming, private: true)
    create(:message, account: account, inbox: inbox, conversation: historical, sender: agent, message_type: :outgoing)
    create(:message, account: account, inbox: inbox, conversation: historical, sender: agent, message_type: :activity)

    expect(historical.reload.auto_assignment_requested_at).to be_nil
    expect(AutoAssignment::AssignmentService.new(inbox: inbox).perform_bulk_assignment).to eq(0)
  end

  it 'does not turn policy correction, message edits, unrelated updates or recovery into a new inbound event' do
    inbox.inbox_assignment_policy.destroy!
    inbox.reload
    message = create(:message, account: account, inbox: inbox, conversation: historical, sender: historical.contact, message_type: :incoming)
    expect(historical.reload.auto_assignment_requested_at).to be_nil

    create(:inbox_assignment_policy, inbox: inbox, assignment_policy: policy)
    inbox.reload
    message.update!(content: 'Corrected message text')
    historical.update!(priority: :high)
    historical.update_columns(last_activity_at: Time.current)
    AutoAssignment::PeriodicAssignmentJob.perform_now
    AutoAssignment::AssignmentJob.perform_now(inbox_id: inbox.id)

    expect(historical.reload.auto_assignment_requested_at).to be_nil
    expect(historical.assignee_id).to be_nil
  end

  it 'does not replace a manual assignee when a new incoming message arrives' do
    historical.update!(assignee: agent)
    create(:message, account: account, inbox: inbox, conversation: historical, sender: historical.contact, message_type: :incoming)

    expect(historical.reload.auto_assignment_requested_at).to be_nil
    expect(historical.assignee_id).to eq(agent.id)
  end

  context 'with legacy assignment' do
    before do
      account.disable_features!('assignment_v2')
      inbox.update!(enable_auto_assignment: false)
      historical
      untouched
      inbox.update!(enable_auto_assignment: true)
    end

    it 'queues legacy assignment after the message event without assigning synchronously or sweeping another row' do
      expect do
        create(:message, account: account, inbox: inbox, conversation: historical, sender: historical.contact, message_type: :incoming)
      end.to have_enqueued_job(AutoAssignment::IncomingAssignmentJob).with(account.id, historical.id)

      expect(historical.reload.assignee_id).to be_nil
      AutoAssignment::IncomingAssignmentJob.perform_now(account.id, historical.id)

      expect(historical.reload.assignee_id).to eq(agent.id)
      expect(untouched.reload.assignee_id).to be_nil
      expect(untouched.auto_assignment_requested_at).to be_nil
    end

    it 'preserves NICO control established before the incoming message' do
      historical.update!(custom_attributes: { 'nico_control' => 'active' })
      create(:message, account: account, inbox: inbox, conversation: historical, sender: historical.contact, message_type: :incoming)
      AutoAssignment::IncomingAssignmentJob.perform_now(account.id, historical.id)

      expect(historical.reload.assignee_id).to be_nil
      expect(historical.custom_attributes['nico_control']).to eq('active')
    end

    it 'does not bypass a human policy enabled after the legacy job was queued' do
      create(:message, account: account, inbox: inbox, conversation: historical, sender: historical.contact, message_type: :incoming)
      account.update!(custom_attributes: {
                        'jrc_human_assignment' => { 'enabled' => true, 'max_open' => 3, 'inbox_ids' => [inbox.id] }
                      })
      team = create(:team, account: account, allow_auto_assign: true)
      create(:team_member, team: team, user: agent)
      historical.update!(team: team)

      AutoAssignment::IncomingAssignmentJob.perform_now(account.id, historical.id)
      expect(historical.reload.assignee_id).to be_nil

      JrcHumanAssignment::DispatchJob.perform_now(account.id)
      expect(historical.reload.assignee_id).to eq(agent.id)
    end

    it 'rechecks NICO control established by the message dispatcher before assignment' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_wrap_original do |original, name, *args|
        historical.update!(custom_attributes: { 'nico_control' => 'active' }) if name == Events::Types::MESSAGE_CREATED
        original.call(name, *args)
      end

      create(:message, account: account, inbox: inbox, conversation: historical, sender: historical.contact, message_type: :incoming)
      AutoAssignment::IncomingAssignmentJob.perform_now(account.id, historical.id)

      expect(historical.reload.assignee_id).to be_nil
      expect(historical.custom_attributes['nico_control']).to eq('active')
    end
  end

  it 'retains the live-flow boundary when a historical conversation receives an incoming message' do
    flow = JrcFlow.create!(account: account, name: 'Synthetic inbound boundary',
                           graph: { 'nodes' => [{ 'id' => 'start', 'type' => 'start', 'label' => 'Start',
                                                 'position' => { 'x' => 0, 'y' => 0 }, 'data' => {} }], 'edges' => [] },
                           settings: { 'inbox_ids' => [], 'days' => [] })
    flow.runs.create!(account: account, conversation: historical, event_key: SecureRandom.uuid,
                      graph: flow.graph, settings: {}, status: 'waiting')
    create(:message, account: account, inbox: inbox, conversation: historical, sender: historical.contact, message_type: :incoming)

    expect(historical.reload.auto_assignment_requested_at).to be_present
    expect(AutoAssignment::AssignmentService.new(inbox: inbox).perform_bulk_assignment).to eq(0)
    expect(historical.reload.assignee_id).to be_nil
  end

  it 'requests human distribution for this incoming event without recovering unrelated historical rows' do
    historical
    untouched
    account.update!(custom_attributes: {
                      'jrc_human_assignment' => { 'enabled' => true, 'max_open' => 3, 'inbox_ids' => [inbox.id] }
                    })
    team = create(:team, account: account, allow_auto_assign: true)
    create(:team_member, team: team, user: agent)
    historical.update!(team: team)
    untouched.update!(team: team)
    create(:message, account: account, inbox: inbox, conversation: historical, sender: historical.contact, message_type: :incoming)

    expect(historical.reload.auto_assignment_requested_at).to be_present
    JrcHumanAssignment::DispatchJob.perform_now(account.id)

    expect(historical.reload.assignee_id).to eq(agent.id)
    expect(untouched.reload.assignee_id).to be_nil
    expect(untouched.auto_assignment_requested_at).to be_nil
  end
end
