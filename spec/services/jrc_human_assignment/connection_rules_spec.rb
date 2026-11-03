require 'rails_helper'

RSpec.describe 'Connection availability and fallback rules' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false, working_hours_enabled: true, timezone: 'America/Sao_Paulo') }
  let(:team) { create(:team, account: account, allow_auto_assign: true) }
  let(:fallback_team) { create(:team, account: account, allow_auto_assign: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:input) do
    { enabled: true, mode: 'round_robin', team_ids: [team.id], max_open: 1, respect_availability: true,
      capacity_enabled: true, waiting_enabled: true, schedule: 'inbox', fallback: 'waiting', fallback_team_id: nil }
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:team_member, team: team, user: agent)
    allow(OnlineStatusTracker).to receive(:effective_available_users).with(account.id).and_return(agent.id.to_s => 'online')
  end

  it 'retains a waiting request outside its local calendar and assigns when the calendar opens' do
    travel_to Time.zone.parse('2026-11-02 10:00:00 UTC') do
      JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **input)
      conversation.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: Time.current)
      2.times { JrcHumanAssignment::Dispatch.new(conversation).perform }
      expect(conversation.reload.assignee_id).to be_nil
      expect(conversation.auto_assignment_requested_at).to be_present
      expect(JrcBrokerConnectionEvent.where(account: account, event_type: 'DISTRIBUTION_FALLBACK').count).to eq(1)
    end
    travel_to Time.zone.parse('2026-11-02 13:00:00 UTC') do
      expect(JrcHumanAssignment::Dispatch.new(conversation).perform).to be(true)
      expect(conversation.reload.assignee_id).to eq(agent.id)
    end
  end

  it 'routes outside hours to the configured fallback team without consuming an agent or retrying' do
    travel_to Time.zone.parse('2026-11-02 10:00:00 UTC') do
      JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin,
                                                   **input.merge(fallback: 'default_team', fallback_team_id: fallback_team.id))
      conversation.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: Time.current)
      JrcHumanAssignment::Dispatch.new(conversation).perform
      expect(conversation.reload).to have_attributes(inbox_id: inbox.id, team_id: fallback_team.id, assignee_id: nil,
                                                     auto_assignment_requested_at: nil)
    end
  end

  it 'leaves an unavailable destination unassigned when waiting is disabled' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin,
                                                 **input.merge(schedule: 'always', waiting_enabled: false, fallback: 'unassigned'))
    allow(OnlineStatusTracker).to receive(:effective_available_users).with(account.id).and_return({})
    conversation.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: Time.current)
    JrcHumanAssignment::Dispatch.new(conversation).perform
    expect(conversation.reload).to have_attributes(team_id: nil, assignee_id: nil, auto_assignment_requested_at: nil)
  end

  it 'does not duplicate fallback audit when polling the same waiting request without eligible agents' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **input.merge(schedule: 'always'))
    allow(OnlineStatusTracker).to receive(:effective_available_users).with(account.id).and_return({})
    conversation.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: Time.current)
    2.times { JrcHumanAssignment::Dispatch.new(conversation).perform }
    expect(JrcBrokerConnectionEvent.where(account: account, event_type: 'DISTRIBUTION_FALLBACK').count).to eq(1)
    expect(conversation.reload.auto_assignment_requested_at).to be_present
  end

  it 'can disregard presence and the connection capacity while keeping membership and opt-out rules' do
    account.account_users.find_by!(user: agent).update!(availability: :offline)
    allow(OnlineStatusTracker).to receive(:effective_available_users).with(account.id).and_return({})
    create(:conversation, account: account, inbox: inbox, assignee: agent, status: :open)
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin,
                                                 **input.merge(schedule: 'always', respect_availability: false, capacity_enabled: false))
    conversation.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: Time.current)
    expect(JrcHumanAssignment::Dispatch.new(conversation).perform).to be(true)
    expect(conversation.reload.assignee_id).to eq(agent.id)
  end

  it 'rejects a foreign fallback, invalid switches and a missing active calendar atomically' do
    foreign = create(:team, account: create(:account))
    inbox.update!(working_hours_enabled: false)
    [input, input.merge(schedule: 'always', respect_availability: 'false'),
     input.merge(schedule: 'always', fallback: 'default_team', fallback_team_id: foreign.id),
     input.merge(schedule: 'always', waiting_enabled: false)].each do |options|
      expect { JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options) }.to raise_error(ArgumentError)
    end
    expect(JrcHumanAssignmentPolicyEvent.where(account: account)).to be_empty
  end
end
