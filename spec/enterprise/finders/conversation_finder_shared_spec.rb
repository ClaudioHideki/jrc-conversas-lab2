require 'rails_helper'

RSpec.describe ConversationFinder do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:other_agent) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }

  before do
    Current.account = account
    create(:inbox_member, inbox: inbox, user: agent)
  end

  %w[conversation_participating_manage conversation_unassigned_manage].each do |permission|
    it "keeps #{permission} individual even with a forged shared filter" do
      role = create(:custom_role, account: account, permissions: [permission])
      account.account_users.find_by!(user: agent).update!(custom_role: role)
      mine = create(:conversation, account: account, inbox: inbox, assignee: agent)
      create(:conversation, account: account, inbox: inbox, assignee: other_agent)
      create(:conversation, account: account, inbox: inbox)

      result = described_class.new(agent, { assignee_type: 'mine_or_shared' }).perform
      expect(result[:conversations].map(&:id)).to eq([mine.id])
      expect(result[:shared_scope]).to eq({ enabled: false, inbox_ids: [] })
    end
  end

  it 'allows a custom role with conversation_manage only within its existing member scope' do
    role = create(:custom_role, account: account, permissions: ['conversation_manage'])
    account.account_users.find_by!(user: agent).update!(custom_role: role)
    shared = create(:conversation, account: account, inbox: inbox, assignee: other_agent)
    create(:conversation, account: account, inbox: create(:inbox, account: account))
    result = described_class.new(agent, { assignee_type: 'mine_or_shared' }).perform
    expect(result[:conversations].map(&:id)).to eq([shared.id])
    expect(result[:shared_scope][:enabled]).to be(true)
  end
end
