require 'rails_helper'

RSpec.describe AutoAssignment::AgentAssignmentService do
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let!(:inbox_members) { create_list(:inbox_member, 5, inbox: inbox) }
  let!(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let!(:online_users) do
    {
      inbox_members[0].user_id.to_s => 'busy',
      inbox_members[1].user_id.to_s => 'busy',
      inbox_members[2].user_id.to_s => 'busy',
      inbox_members[3].user_id.to_s => 'online',
      inbox_members[4].user_id.to_s => 'online'
    }
  end

  before do
    account.disable_features!('assignment_v2')
    inbox_members.each { |inbox_member| create(:account_user, account: account, user: inbox_member.user) }
    allow(OnlineStatusTracker).to receive(:effective_available_users).and_return(online_users)
    inbox.update!(enable_auto_assignment: true)
  end

  describe '#perform' do
    it 'will assign an online agent to the conversation' do
      expect(conversation.reload.assignee).to be_nil
      described_class.new(conversation: conversation, allowed_agent_ids: inbox_members.map(&:user_id).map(&:to_s)).perform
      expect(conversation.reload.assignee).not_to be_nil
    end

    it 'locks a persisted copy without losing the caller creation event or trigger-generated display id' do
      event_changes = conversation.previous_changes.deep_dup
      display_id = conversation.display_id

      described_class.new(conversation: conversation, allowed_agent_ids: inbox_members.map(&:user_id)).perform

      expect(conversation.previous_changes).to eq(event_changes)
      expect(conversation.display_id).to eq(display_id)
      expect(conversation.assignee_id).to eq(inbox_members[3].user_id)
      expect(conversation.will_save_change_to_assignee_id?).to be(false)
      expect(Conversation.find(conversation.id).assignee_id).to eq(inbox_members[3].user_id)
    end

    it 'preserves a newer manual assignment when the caller has a stale unassigned instance' do
      manual_agent = inbox_members[4].user
      Conversation.find(conversation.id).update!(assignee: manual_agent)

      described_class.new(conversation: conversation, allowed_agent_ids: inbox_members.map(&:user_id)).perform

      expect(conversation.reload.assignee_id).to eq(manual_agent.id)
    end
  end

  describe '#find_assignee' do
    it 'will return an online agent from the allowed agent ids in roud robin' do
      expect(described_class.new(conversation: conversation,
                                 allowed_agent_ids: inbox_members.map(&:user_id).map(&:to_s)).find_assignee).to eq(inbox_members[3].user)
      expect(described_class.new(conversation: conversation,
                                 allowed_agent_ids: inbox_members.map(&:user_id).map(&:to_s)).find_assignee).to eq(inbox_members[4].user)
    end
  end
end
