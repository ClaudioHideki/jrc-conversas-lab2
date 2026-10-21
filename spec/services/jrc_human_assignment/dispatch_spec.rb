require 'rails_helper'

RSpec.describe JrcHumanAssignment::Dispatch do
  let(:account) { create(:account, custom_attributes: { 'jrc_human_assignment' => { 'enabled' => true, 'max_open' => 3 } }) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:second_inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:team) { create(:team, account: account, allow_auto_assign: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }

  before do
    account.update!(custom_attributes: account.custom_attributes.deep_merge(
      'jrc_human_assignment' => { 'inbox_ids' => [inbox.id, second_inbox.id] }
    ))
    [agent, other_agent].each do |member|
      create(:inbox_member, inbox: inbox, user: member)
      create(:team_member, team: team, user: member)
    end
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id)
      .and_return(agent.id.to_s => 'online', other_agent.id.to_s => 'online')
    conversation.update_columns(team_id: team.id, assignee_id: nil)
  end

  it 'counts the workload in other inboxes and preserves the original reply channel' do
    create(:conversation, account: account, inbox: second_inbox, assignee: agent, status: :open)
    expect(described_class.new(conversation).perform).to be(true)
    expect(conversation.reload.assignee_id).to eq(other_agent.id)
    expect(conversation.inbox_id).to eq(inbox.id)
    expect(conversation.team_id).to eq(team.id)
  end

  it 'does not count workload from another tenant for a shared employee' do
    foreign = create(:account)
    create(:account_user, account: foreign, user: agent)
    foreign_inbox = create(:inbox, account: foreign, enable_auto_assignment: false)
    create(:conversation, account: foreign, inbox: foreign_inbox, assignee: agent, status: :open)
    account.update!(custom_attributes: account.custom_attributes.deep_merge('jrc_human_assignment' => { 'last_agent_id' => other_agent.id }))
    described_class.new(conversation).perform
    expect(conversation.reload.assignee_id).to eq([agent.id, other_agent.id].min)
  end

  it 'keeps a human queue when agents are offline and resumes it when someone becomes available' do
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({})
    expect(described_class.new(conversation).perform).to be(false)
    expect(conversation.reload.assignee_id).to be_nil
    expect(conversation.status).to eq('open')
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(agent.id.to_s => 'online')
    JrcHumanAssignment::DispatchJob.perform_now(account.id)
    expect(conversation.reload.assignee_id).to eq(agent.id)
  end

  it 'never assigns outside both inbox and team membership' do
    team.team_members.find_by!(user_id: agent.id).destroy!
    inbox.inbox_members.find_by!(user_id: other_agent.id).destroy!
    expect(described_class.new(conversation).perform).to be(false)
    expect(conversation.reload.assignee_id).to be_nil
  end

  it 'preserves a manual assignee and does not exceed aggregate capacity' do
    conversation.update_columns(assignee_id: other_agent.id)
    expect(described_class.new(conversation).perform).to be(false)
    expect(conversation.reload.assignee_id).to eq(other_agent.id)
    conversation.update_columns(assignee_id: nil)
    [agent, other_agent].each { |member| create_list(:conversation, 3, account: account, inbox: second_inbox, assignee: member, status: :open) }
    expect(described_class.new(conversation).perform).to be(false)
  end

  it 'does not assign a pending conversation or one held by an agent bot' do
    conversation.update_columns(status: Conversation.statuses.fetch('pending'))
    expect(described_class.new(conversation).perform).to be(false)
    conversation.update_columns(status: Conversation.statuses.fetch('open'), assignee_agent_bot_id: create(:agent_bot, account: account).id)
    expect(described_class.new(conversation).perform).to be(false)
  end

  it 'does not enable the policy for other accounts by default' do
    account.update!(custom_attributes: {})
    expect(described_class.new(conversation).perform).to be(false)
  end

  it 'skips an agent with pending contact-center tabulation without bypassing the assignment guard' do
    account.enable_features!('jrc_contact_center')
    member = account.account_users.find_by!(user: agent)
    ended_call = JrcContactCenter::CallSession.create!(
      account: account, provider: 'jrc_pabx', correlation_id: 'synthetic-pending-acw',
      direction: 'inbound', status: 'ended', started_at: 2.minutes.ago, ended_at: Time.current
    )
    JrcContactCenter::Qualification.create!(
      account: account, account_user: member, call_session: ended_call, channel: 'voice',
      started_at: Time.current, acw_limit_seconds: 180
    )

    expect(described_class.new(conversation).perform).to be(true)
    expect(conversation.reload.assignee_id).to eq(other_agent.id)
    expect(JrcContactCenter::Qualification.pending.where(account: account, account_user: member)).to exist
  end

  it 'waits for NICO and a live native flow to release the conversation' do
    conversation.update_columns(custom_attributes: { 'nico_control' => 'active' })
    expect(described_class.new(conversation).perform).to be(false)
    conversation.update_columns(custom_attributes: {})
    flow = JrcFlow.create!(account: account, name: 'Synthetic assignment boundary',
                           graph: { 'nodes' => [{ 'id' => 'start', 'type' => 'start', 'label' => 'Start',
                                                 'position' => { 'x' => 0, 'y' => 0 }, 'data' => {} }], 'edges' => [] },
                           settings: { 'inbox_ids' => [], 'days' => [] })
    run = flow.runs.create!(account: account, conversation: conversation, event_key: SecureRandom.uuid,
                            graph: flow.graph, settings: {}, status: 'waiting')
    expect(described_class.new(conversation).perform).to be(false)
    run.update!(status: 'completed')
    expect(described_class.new(conversation).perform).to be(true)
  end

  it 'waits for team selection instead of assigning a new inbox arrival before the URA' do
    inbox.update!(enable_auto_assignment: true)
    arrival = create(:conversation, account: account, inbox: inbox, status: :open)
    expect(arrival.reload.assignee_id).to be_nil
    expect(arrival.team_id).to be_nil
    expect(AutoAssignment::AssignmentService.new(inbox: inbox).perform_bulk_assignment).to eq(0)
  end

  it 'preserves native legacy assignment in an inbox outside the selected URA inboxes' do
    account.disable_features!('assignment_v2')
    account.update!(custom_attributes: account.custom_attributes.deep_merge(
      'jrc_human_assignment' => { 'inbox_ids' => [inbox.id] }
    ))
    unrelated = create(:inbox, account: account, enable_auto_assignment: true)
    create(:inbox_member, inbox: unrelated, user: agent)
    arrival = create(:conversation, account: account, inbox: unrelated, status: :open)
    expect(arrival.reload.assignee_id).to eq(agent.id)
  end

  it 'preserves native queued assignment V2 outside the selected URA inboxes' do
    account.enable_features!('assignment_v2')
    unrelated = create(:inbox, account: account, enable_auto_assignment: true)
    create(:inbox_member, inbox: unrelated, user: agent)
    arrival = create(:conversation, account: account, inbox: unrelated, status: :open)
    expect(arrival.reload.assignee_id).to be_nil
    expect(AutoAssignment::AssignmentService.new(inbox: unrelated).perform_bulk_assignment).to eq(1)
    expect(arrival.reload.assignee_id).to eq(agent.id)
    expect(conversation.reload.assignee_id).to be_nil
  end

  it 'continues beyond a page of unavailable teams instead of starving another inbox' do
    stub_const('JrcHumanAssignment::DispatchJob::BATCH_SIZE', 2)
    unavailable = create(:team, account: account, allow_auto_assign: false)
    conversation.update_columns(team_id: unavailable.id)
    blocked = create(:conversation, account: account, inbox: inbox, status: :open)
    blocked.update_columns(team_id: unavailable.id, assignee_id: nil)
    waiting = create(:conversation, account: account, inbox: inbox, status: :open)
    waiting.update_columns(team_id: team.id, assignee_id: nil)
    expect { JrcHumanAssignment::DispatchJob.perform_now(account.id) }
      .to have_enqueued_job(JrcHumanAssignment::DispatchJob).with(account.id, blocked.id)
    JrcHumanAssignment::DispatchJob.perform_now(account.id, blocked.id)
    expect(waiting.reload.assignee_id).to be_present
    expect(conversation.reload.assignee_id).to be_nil
  end
end
