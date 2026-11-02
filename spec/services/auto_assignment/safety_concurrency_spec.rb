require 'rails_helper'

RSpec.describe 'Automatic assignment concurrency', :sd_concurrency do
  self.use_transactional_tests = false
  include JrcServiceDeskConcurrency

  it 'claims the same conversation once when two workers run concurrently' do
    account = create(:account)
    account.enable_features!('assignment_v2')
    inbox = create(:inbox, account: account)
    agent = create(:user, account: account)
    create(:inbox_member, inbox: inbox, user: agent)
    create(:inbox_assignment_policy, inbox: inbox, assignment_policy: create(:assignment_policy, account: account))
    conversation = create(:conversation, account: account, inbox: inbox)
    OnlineStatusTracker.update_presence(account.id, 'User', agent.id)

    results = concurrently(Array.new(2) do
      -> { AutoAssignment::AssignmentService.new(inbox: Inbox.find(inbox.id)).perform_bulk_assignment }
    end)

    expect(results.sort).to eq([0, 1])
    expect(conversation.reload.assignee_id).to eq(agent.id)
    expect(conversation.auto_assignment_requested_at).to be_nil
  end

  it 'serializes the last capacity slot across two workers' do
    account = create(:account)
    account.enable_features!('assignment_v2', 'advanced_assignment')
    inbox = create(:inbox, account: account)
    agent = create(:user, account: account)
    create(:inbox_member, inbox: inbox, user: agent)
    create(:inbox_assignment_policy, inbox: inbox, assignment_policy: create(:assignment_policy, account: account))
    capacity = create(:agent_capacity_policy, account: account)
    create(:inbox_capacity_limit, inbox: inbox, agent_capacity_policy: capacity, conversation_limit: 1)
    account.account_users.find_by!(user: agent).update!(agent_capacity_policy: capacity)
    create_list(:conversation, 2, account: account, inbox: inbox)
    OnlineStatusTracker.update_presence(account.id, 'User', agent.id)

    results = concurrently(Array.new(2) do
      -> { AutoAssignment::AssignmentService.new(inbox: Inbox.find(inbox.id)).perform_bulk_assignment }
    end)

    expect(results.sum).to eq(1)
    expect(inbox.conversations.open.where(assignee_id: agent.id).count).to eq(1)
    expect(inbox.conversations.unassigned.count).to eq(1)
  end

  it 'reserves the last rate-limit slot before releasing the account lock' do
    account = create(:account)
    account.enable_features!('assignment_v2')
    inbox = create(:inbox, account: account)
    agent = create(:user, account: account)
    create(:inbox_member, inbox: inbox, user: agent)
    policy = create(:assignment_policy, account: account, fair_distribution_limit: 1)
    create(:inbox_assignment_policy, inbox: inbox, assignment_policy: policy)
    conversations = create_list(:conversation, 2, account: account, inbox: inbox)
    OnlineStatusTracker.update_presence(account.id, 'User', agent.id)

    results = concurrently(conversations.map do |conversation|
      lambda do
        service = AutoAssignment::AssignmentService.new(inbox: Inbox.find(inbox.id))
        service.send(:claim_and_assign, Conversation.find(conversation.id), agent)
      end
    end)

    expect(results.count(true)).to eq(1)
    expect(results.count(false)).to eq(1)
    expect(inbox.conversations.open.where(assignee_id: agent.id).count).to eq(1)
    expect(AutoAssignment::RateLimiter.new(inbox: inbox, agent: agent).current_count).to eq(1)
  end
end
