require 'rails_helper'

RSpec.describe 'Legacy automatic assignment on reopening' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: true) }
  let(:previous_agent) { create(:user, account: account) }
  let(:candidate) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: previous_agent, status: :resolved) }

  before do
    account.disable_features!('assignment_v2')
    create(:inbox_member, inbox: inbox, user: candidate)
    OnlineStatusTracker.update_presence(account.id, 'User', candidate.id)
  end

  it 'replaces an inaccessible assignee on an explicit reopening' do
    conversation.update!(status: :open)

    expect(conversation.reload.assignee_id).to eq(candidate.id)
  end

  it 'preserves an accessible current assignee' do
    create(:inbox_member, inbox: inbox, user: previous_agent)
    conversation.update!(status: :open)

    expect(conversation.reload.assignee_id).to eq(previous_agent.id)
  end

  it 'preserves the current assignee when automatic assignment is disabled' do
    inbox.update!(enable_auto_assignment: false)
    conversation.update!(status: :open)

    expect(conversation.reload.assignee_id).to eq(previous_agent.id)
  end

  it 'preserves the current assignee without effective candidate presence' do
    travel OnlineStatusTracker::PRESENCE_DURATION + 1.second do
      conversation.update!(status: :open)
      expect(conversation.reload.assignee_id).to eq(previous_agent.id)
    end
  end

  it 'does not use an individually excluded candidate for replacement' do
    account.account_users.find_by!(user: candidate).update!(auto_assignment_enabled: false)
    conversation.update!(status: :open)

    expect(conversation.reload.assignee_id).to eq(previous_agent.id)
  end

  it 'does not bypass a missing V2 policy through the legacy replacement path' do
    account.enable_features!('assignment_v2')
    conversation.update!(status: :open)

    expect(conversation.reload.assignee_id).to eq(previous_agent.id)
    expect(conversation.auto_assignment_requested_at).to be_nil
  end

  it 'does not replace an existing assignee on an unrelated update' do
    conversation.update_columns(status: Conversation.statuses.fetch('open'))
    conversation.update!(priority: :high)

    expect(conversation.reload.assignee_id).to eq(previous_agent.id)
  end
end
