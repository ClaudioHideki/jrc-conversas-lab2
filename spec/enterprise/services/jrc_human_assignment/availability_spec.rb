require 'rails_helper'

RSpec.describe 'Enterprise connection availability and capacity' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: true) }
  let(:team) { create(:team, account: account, allow_auto_assign: true) }
  let(:agent) { create(:user, account: account, role: :agent, auto_offline: false) }
  let(:capacity_policy) { create(:agent_capacity_policy, account: account) }
  let(:respect_availability) { false }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }

  before do
    account.enable_features!('assignment_v2', 'advanced_assignment')
    create(:inbox_member, inbox: inbox, user: agent)
    create(:team_member, team: team, user: agent)
    create(:inbox_capacity_limit, agent_capacity_policy: capacity_policy, inbox: inbox, conversation_limit: 1)
    account.account_users.find_by!(user: agent).update!(agent_capacity_policy: capacity_policy, availability: :offline)
    allow(OnlineStatusTracker).to receive(:effective_available_users).with(account.id).and_return({})
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, enabled: true,
                                                 mode: 'priority', team_ids: [team.id], max_open: 10,
                                                 respect_availability: respect_availability)
  end

  it 'keeps the default online-only capacity query and admits an offline member only when explicitly requested' do
    expect(inbox.member_ids_with_assignment_capacity).to be_empty
    expect(inbox.member_ids_with_assignment_capacity(respect_availability: false)).to contain_exactly(agent.id)
  end

  it 'uses the availability option in the final eligibility capacity recheck' do
    member = account.account_users.find_by!(user: agent)

    expect(AutoAssignment::Eligibility.new(inbox: inbox).agent_reason(member)).to eq('agent_unavailable')
    expect(AutoAssignment::Eligibility.new(inbox: inbox).agent_reason(member, respect_availability: false)).to be_nil
  end

  it 'assigns an offline member with capacity when connection availability is disabled' do
    conversation.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: Time.current)

    expect(JrcHumanAssignment::Dispatch.new(conversation).perform).to be(true)
    expect(conversation.reload.assignee_id).to eq(agent.id)
  end

  it 'retains Enterprise capacity limits even when availability is disabled' do
    create(:conversation, account: account, inbox: inbox, assignee: agent, status: :open)
    conversation.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: Time.current)

    expect(inbox.member_ids_with_assignment_capacity(respect_availability: false)).to be_empty
    expect(JrcHumanAssignment::Dispatch.new(conversation).perform).to be(false)
    expect(conversation.reload.assignee_id).to be_nil
  end

  it 'retains Enterprise capacity when the JRC policy operates with native auto-assignment disabled' do
    inbox.update!(enable_auto_assignment: false)
    create(:conversation, account: account, inbox: inbox, assignee: agent, status: :open)

    expect(inbox.member_ids_with_assignment_capacity(respect_availability: false)).to be_empty
  end

  it 'retains Enterprise capacity when the account uses native assignment V1' do
    account.disable_features!('assignment_v2')
    create(:conversation, account: account, inbox: inbox, assignee: agent, status: :open)

    expect(inbox.member_ids_with_assignment_capacity(respect_availability: false)).to be_empty
  end

  it 'retains account opt-out even when availability is disabled' do
    account.account_users.find_by!(user: agent).update!(auto_assignment_enabled: false)
    conversation.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: Time.current)

    expect(JrcHumanAssignment::Dispatch.new(conversation).perform).to be(false)
    expect(conversation.reload.assignee_id).to be_nil
  end

  it 'retains inbox membership restrictions even when availability is disabled' do
    inbox.inbox_members.find_by!(user: agent).destroy!
    conversation.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: Time.current)

    expect(JrcHumanAssignment::Dispatch.new(conversation).perform).to be(false)
    expect(conversation.reload.assignee_id).to be_nil
  end

  context 'when connection availability is enabled' do
    let(:respect_availability) { true }

    it 'keeps the offline member waiting rather than assigning' do
      conversation.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: Time.current)

      expect(JrcHumanAssignment::Dispatch.new(conversation).perform).to be(false)
      expect(conversation.reload.assignee_id).to be_nil
    end
  end
end
