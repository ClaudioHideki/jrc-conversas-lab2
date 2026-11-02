require 'rails_helper'

RSpec.describe 'Automatic assignment safety contract' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: true) }
  let(:policy) { create(:assignment_policy, account: account) }
  let(:agent) { create(:user, account: account, role: :administrator) }
  let(:account_user) { account.account_users.find_by!(user: agent) }
  let(:service) { AutoAssignment::AssignmentService.new(inbox: inbox) }

  before do
    account.enable_features!('assignment_v2')
    create(:inbox_assignment_policy, inbox: inbox, assignment_policy: policy)
    create(:inbox_member, inbox: inbox, user: agent)
    OnlineStatusTracker.update_presence(account.id, 'User', agent.id)
  end

  it 'assigns a new open event once and leaves an unrequested historical row untouched' do
    historical = create(:conversation, account: account, inbox: inbox)
    historical.update_columns(auto_assignment_requested_at: nil)
    arrival = create(:conversation, account: account, inbox: inbox)

    expect(service.perform_bulk_assignment).to eq(1)
    expect(service.perform_bulk_assignment).to eq(0)
    expect(arrival.reload.assignee_id).to eq(agent.id)
    expect(arrival.auto_assignment_requested_at).to be_nil
    expect(historical.reload.assignee_id).to be_nil
  end

  it 'does not create policies or requests when policy is absent, including after administrative correction' do
    inbox.inbox_assignment_policy.destroy!
    inbox.reload
    arrival = create(:conversation, account: account, inbox: inbox)
    expect(arrival.auto_assignment_requested_at).to be_nil
    expect(service.perform_bulk_assignment).to eq(0)
    expect(AutoAssignment::Diagnostics.new(inbox: inbox).perform[:reason]).to eq('policy_missing')

    create(:inbox_assignment_policy, inbox: inbox, assignment_policy: policy)
    inbox.reload
    expect(service.perform_bulk_assignment).to eq(0)
    expect(arrival.reload.assignee_id).to be_nil
    arrival.update!(status: :resolved)
    arrival.update!(status: :open)
    expect(arrival.reload.auto_assignment_requested_at).to be_present
    expect(service.perform_bulk_assignment).to eq(1)
  end

  it 'keeps a new request pending without active presence even when auto_offline is false' do
    account_user.update!(auto_offline: false)
    arrival = create(:conversation, account: account, inbox: inbox)
    travel OnlineStatusTracker::PRESENCE_DURATION + 1.second do
      expect(service.perform_bulk_assignment).to eq(0)
      expect(arrival.reload.auto_assignment_requested_at).to be_present
      OnlineStatusTracker.update_presence(account.id, 'User', agent.id)
      expect(service.perform_bulk_assignment).to eq(1)
    end
  end

  it 'does not assign on Redis presence failure' do
    arrival = create(:conversation, account: account, inbox: inbox)
    allow(Redis::Alfred).to receive(:zrangebyscore).and_raise(Redis::CannotConnectError)

    expect(service.perform_bulk_assignment).to eq(0)
    expect(arrival.reload.assignee_id).to be_nil
    expect(AutoAssignment::Diagnostics.new(inbox: inbox).perform[:reason]).to eq('redis_presence_unavailable')
  end

  it 'preserves role, team, inbox and existing manual assignments for an individually excluded administrator' do
    team = create(:team, account: account)
    create(:team_member, team: team, user: agent)
    assigned = create(:conversation, account: account, inbox: inbox, assignee: agent)
    account_user.update!(auto_assignment_enabled: false)
    arrival = create(:conversation, account: account, inbox: inbox)

    expect(service.perform_bulk_assignment).to eq(0)
    expect(arrival.reload.assignee_id).to be_nil
    expect(assigned.reload.assignee_id).to eq(agent.id)
    expect(account_user.reload).to be_administrator
    expect(team.members).to include(agent)
    expect(inbox.members).to include(agent)
    arrival.update!(assignee: agent)
    expect(arrival.reload.assignee_id).to eq(agent.id)
  end

  it 'rechecks exclusion immediately before the final write' do
    arrival = create(:conversation, account: account, inbox: inbox)
    allow(service).to receive(:find_available_agent) do
      account_user.update!(auto_assignment_enabled: false)
      agent
    end

    expect(service.perform_bulk_assignment).to eq(0)
    expect(arrival.reload.assignee_id).to be_nil
  end

  it 'rechecks presence immediately before the final write' do
    arrival = create(:conversation, account: account, inbox: inbox)
    allow(service).to receive(:find_available_agent) do
      account_user.update!(availability: :offline)
      agent
    end

    expect(service.perform_bulk_assignment).to eq(0)
    expect(arrival.reload.assignee_id).to be_nil
  end

  it 'rechecks team membership even when a selector returns an unsuitable agent' do
    team = create(:team, account: account, allow_auto_assign: true)
    arrival = create(:conversation, account: account, inbox: inbox, team: team)
    allow(service).to receive(:find_available_agent).and_return(agent)

    expect(service.perform_bulk_assignment).to eq(0)
    expect(arrival.reload.assignee_id).to be_nil
  end

  it 'rereads policy exclusions after selection before the final write' do
    arrival = create(:conversation, account: account, inbox: inbox, last_activity_at: 2.hours.ago)
    allow(service).to receive(:find_available_agent) do
      policy.update!(exclude_older_than_hours: 1)
      agent
    end

    expect(service.perform_bulk_assignment).to eq(0)
    expect(arrival.reload.assignee_id).to be_nil
    expect(arrival.auto_assignment_requested_at).to be_present
  end

  it 'does not complete a V2 assignment if V2 is disabled after selection' do
    arrival = create(:conversation, account: account, inbox: inbox)
    allow(service).to receive(:find_available_agent) do
      account.disable_features!('assignment_v2')
      agent
    end

    expect(service.perform_bulk_assignment).to eq(0)
    expect(arrival.reload.assignee_id).to be_nil
  end

  it 'rolls back the assignment if Redis cannot record the rate-limit reservation' do
    arrival = create(:conversation, account: account, inbox: inbox)
    limiter = instance_double(AutoAssignment::RateLimiter, within_limit?: true)
    allow(AutoAssignment::RateLimiter).to receive(:new).and_return(limiter)
    allow(limiter).to receive(:track_assignment).and_raise(Redis::CannotConnectError)

    expect { service.perform_bulk_assignment }.to(raise_error { |error| expect(error.class.name).to eq('Redis::CannotConnectError') })
    expect(arrival.reload.assignee_id).to be_nil
    expect(arrival.auto_assignment_requested_at).to be_present
  end

  it 'preserves the NICO control boundary' do
    arrival = create(:conversation, account: account, inbox: inbox, custom_attributes: { 'nico_control' => 'active' })

    expect(service.perform_bulk_assignment).to eq(0)
    expect(arrival.reload.assignee_id).to be_nil
  end

  it 'rechecks enterprise capacity if another assignment consumes the last slot after selection' do
    account.enable_features!('advanced_assignment')
    capacity = create(:agent_capacity_policy, account: account)
    create(:inbox_capacity_limit, inbox: inbox, agent_capacity_policy: capacity, conversation_limit: 1)
    account_user.update!(agent_capacity_policy: capacity)
    arrival = create(:conversation, account: account, inbox: inbox)
    allow(service).to receive(:find_available_agent) do
      create(:conversation, account: account, inbox: inbox, assignee: agent)
      agent
    end

    expect(service.perform_bulk_assignment).to eq(0)
    expect(arrival.reload.assignee_id).to be_nil
  end

  it 'applies individual exclusion to legacy automatic assignment as well' do
    account.disable_features!('assignment_v2')
    account_user.update!(auto_assignment_enabled: false)
    arrival = create(:conversation, account: account, inbox: inbox)

    expect(arrival.reload.assignee_id).to be_nil
    account_user.update!(auto_assignment_enabled: true)
    arrival.update!(status: :resolved)
    arrival.update!(status: :open)
    expect(arrival.reload.assignee_id).to eq(agent.id)
  end

  it 'recovers a new request after a failed job without processing historical backlog' do
    arrival = create(:conversation, account: account, inbox: inbox)
    allow(AutoAssignment::AssignmentService).to receive(:new).and_raise(StandardError, 'Synthetic failure')
    expect { AutoAssignment::AssignmentJob.perform_now(inbox_id: inbox.id) }.to raise_error(StandardError, 'Synthetic failure')
    expect(arrival.reload.auto_assignment_requested_at).to be_present
    allow(AutoAssignment::AssignmentService).to receive(:new).and_call_original

    AutoAssignment::AssignmentJob.perform_now(inbox_id: inbox.id)
    expect(arrival.reload.assignee_id).to eq(agent.id)
  end
end
