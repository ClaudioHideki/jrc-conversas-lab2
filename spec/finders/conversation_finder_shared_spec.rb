require 'rails_helper'

describe ConversationFinder do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:other_agent) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:routed_inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:params) { { assignee_type: 'mine_or_shared', include_participating: true } }

  before do
    Current.account = account
    create(:inbox_member, inbox: inbox, user: agent)
    create(:inbox_member, inbox: routed_inbox, user: agent)
    create(:agent_bot_inbox, inbox: routed_inbox, status: :active)
  end

  it 'shares unassigned and other assignments only in member inboxes without automation' do
    mine = create(:conversation, account: account, inbox: routed_inbox, assignee: agent)
    shared = create(:conversation, account: account, inbox: inbox, assignee: other_agent)
    unassigned = create(:conversation, account: account, inbox: inbox)
    create(:conversation, account: account, inbox: routed_inbox, assignee: other_agent)
    create(:conversation, account: account, inbox: create(:inbox, account: account))
    foreign_account = create(:account)
    create(:conversation, account: foreign_account, inbox: create(:inbox, account: foreign_account))

    result = described_class.new(agent, params).perform

    expect(result[:conversations].map(&:id)).to contain_exactly(mine.id, shared.id, unassigned.id)
    expect(result[:count][:mine_count]).to eq(1)
    expect(result[:shared_scope]).to eq({ enabled: true, inbox_ids: [inbox.id] })
  end

  it 'keeps the existing me contract individual' do
    mine = create(:conversation, account: account, inbox: inbox, assignee: agent)
    create(:conversation, account: account, inbox: inbox, assignee: other_agent)
    expect(described_class.new(agent, params.merge(assignee_type: 'me')).perform[:conversations].map(&:id)).to eq([mine.id])
  end

  it 'keeps a bot-assigned conversation outside shared visibility even when its inbox no longer has an active bot' do
    create(:conversation, account: account, inbox: inbox, assignee_agent_bot: create(:agent_bot))
    expect(described_class.new(agent, params).perform[:conversations]).to be_empty
  end

  it 'rechecks membership for each request' do
    create(:conversation, account: account, inbox: inbox, assignee: other_agent)
    expect(described_class.new(agent, params).perform[:conversations].size).to eq(1)
    inbox.inbox_members.where(user: agent).delete_all
    expect(described_class.new(agent, params).perform[:conversations]).to be_empty
  end
end
