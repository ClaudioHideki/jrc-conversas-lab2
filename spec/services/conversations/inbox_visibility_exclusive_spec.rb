require 'rails_helper'

RSpec.describe Conversations::InboxVisibility do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:peer) { create(:user, account: account, role: :agent) }
  let(:supervisor) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }

  before do
    [agent, peer, supervisor].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    account.update!(custom_attributes: { 'jrc_human_assignment' => { 'connections' => {
                      inbox.id.to_s => { 'visibility' => 'assigned_only', 'supervisor_ids' => [supervisor.id] }
                    } } })
  end

  it 'denies a colleague the direct conversation even when they belong to the same inbox' do
    member = account.account_users.find_by!(user: peer)
    expect(ConversationPolicy.new({ user: peer, account: account, account_user: member }, conversation).show?).to be(false)
  end

  it 'removes a colleagues conversation from backend list scopes' do
    expect(Conversations::PermissionFilterService.new(account.conversations, peer, account).perform).not_to include(conversation)
  end

  it 'does not expose an unassigned queue item to a regular agent' do
    conversation.update!(assignee: nil)
    expect(Conversations::PermissionFilterService.new(account.conversations, peer, account).perform).not_to include(conversation)
  end

  it 'keeps the assignee and the configured supervisor authorized' do
    [agent, supervisor, admin].each do |user|
      member = account.account_users.find_by!(user: user)
      expect(ConversationPolicy.new({ user: user, account: account, account_user: member }, conversation).show?).to be(true)
      expect(Conversations::PermissionFilterService.new(account.conversations, user, account).perform).to include(conversation)
    end
  end

  it 'does not let previous participation bypass exclusive access' do
    create(:conversation_participant, account: account, conversation: conversation, user: peer)
    member = account.account_users.find_by!(user: peer)
    expect(ConversationPolicy.new({ user: peer, account: account, account_user: member }, conversation).show?).to be(false)
  end

  it 'preserves the shared inbox behavior when there is no exclusive policy' do
    account.update!(custom_attributes: {})
    expect(Conversations::PermissionFilterService.new(account.conversations, peer, account).perform).to include(conversation)
  end

  it 'does not broadcast message content to a colleague in the exclusive inbox' do
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)
    event = Events::Base.new(:'message.created', Time.current, message: message)
    allow(ActionCableBroadcastJob).to receive(:perform_later)
    ActionCableListener.instance.message_created(event)
    expect(ActionCableBroadcastJob).to have_received(:perform_later).with(
      array_excluding(peer.pubsub_token), 'message.created', anything
    )
  end

  it 'sends content-free transfer revocation only to the previous owner' do
    conversation.update!(assignee: peer)
    event = Events::Base.new(:'assignee.changed', Time.current, conversation: conversation,
                            changed_attributes: { 'assignee_id' => [agent.id, peer.id] })
    allow(ActionCableBroadcastJob).to receive(:perform_later)
    ActionCableListener.instance.assignee_changed(event)
    expect(ActionCableBroadcastJob).to have_received(:perform_later).with(
      [agent.pubsub_token], 'conversation.access_revoked', { id: conversation.display_id, account_id: account.id }
    )
  end

  it 'rechecks visibility when a queued message broadcast executes after a transfer' do
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)
    conversation.update!(assignee: peer)
    allow(ActionCable.server).to receive(:broadcast)
    ActionCableBroadcastJob.perform_now([agent.pubsub_token], 'message.created', message.push_event_data.merge(account_id: account.id))
    expect(ActionCable.server).not_to have_received(:broadcast).with(agent.pubsub_token, anything)
  end

  it 'does not allow a supervisor to retain access after inbox membership removal' do
    inbox.inbox_members.find_by!(user: supervisor).destroy!
    member = account.account_users.find_by!(user: supervisor)
    expect(ConversationPolicy.new({ user: supervisor, account: account, account_user: member }, conversation).show?).to be(false)
  end

  it 'sends a content-free cache reset after removal from an exclusive inbox' do
    member = inbox.inbox_members.find_by!(user: agent)
    expect { member.destroy! }.to have_enqueued_job(ActionCableBroadcastJob).with(
      [agent.pubsub_token], 'conversation.access_reset', { account_id: account.id }
    )
  end

  it 'does not send a queued payload after its conversation was deleted' do
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)
    payload = message.push_event_data.merge(account_id: account.id)
    conversation.destroy!
    allow(ActionCable.server).to receive(:broadcast)
    ActionCableBroadcastJob.perform_now([agent.pubsub_token], 'message.created', payload)
    expect(ActionCable.server).not_to have_received(:broadcast)
  end

  it 'applies the restriction even to a custom role with conversation_manage' do
    role = create(:custom_role, account: account, permissions: ['conversation_manage'])
    account.account_users.find_by!(user: peer).update!(custom_role: role)
    expect(Conversations::PermissionFilterService.new(account.conversations, peer, account).perform).not_to include(conversation)
  end

  it 'includes only the inboxes explicitly supervised by this user in supervision metadata' do
    metadata = Conversations::SharedInboxScope.new(conversations: account.conversations, account: account, user: supervisor).metadata
    expect(metadata[:supervised_inbox_ids]).to eq([inbox.id])
    expect(metadata[:inbox_ids]).not_to include(inbox.id)
  end
end
