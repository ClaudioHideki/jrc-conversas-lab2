require 'rails_helper'

RSpec.describe 'HelpDesk human-approved public acknowledgement', type: :request do
  include_context 'NICO HelpDesk native action chain'

  let(:selected_rule) { 'R10' }
  let(:channel) { create(:channel_whatsapp, account: sd_account, sync_templates: false, validate_provider_config: false) }
  let(:conversation) { create(:conversation, account: sd_account, inbox: channel.inbox, contact: sd_contact) }
  let(:input) do
    { 'reply' => { 'conversation_id' => conversation.display_id,
                  'content' => 'Recebemos sua reclamação. O responsável humano está acompanhando o chamado.' } }
  end

  def linked_customer_conversation
    JrcServiceDesk::TicketConversation.create!(account: sd_account, unit: sd_unit, ticket: ticket,
                                               conversation: conversation, linked_by_membership: sd_membership)
    create(:message, account: sd_account, conversation: conversation, inbox: conversation.inbox,
                     sender: sd_contact, message_type: :incoming, content: 'Mensagem sintética do cliente.', created_at: Time.current)
  end

  before { linked_customer_conversation }

  it 'captures the complaint, reviews exact recipient and queues one native public Message without provider I/O' do
    event
    approval = nil
    expect { approval = prepare_native(input, 'send_message') }.not_to change(Message, :count)
    expect(approval.scope.dig('group', 'resources')).to include(['Conversation', conversation.id], ['JrcNico::ServiceTicketConversations', ticket.id])
    expect(approval.command.arguments).to eq(input.fetch('reply').merge('private' => false))
    expect { approve_native(approval) }.to change(Message, :count).by(1)
    command = approved_action(approval)
    message = conversation.messages.find(command.result.fetch('id'))
    expect(message).to have_attributes(account_id: sd_account.id, inbox_id: conversation.inbox_id, sender: sd_user,
                                        private: false, message_type: 'outgoing', content: input.dig('reply', 'content'))
    expect(conversation.reload.contact_inbox).to have_attributes(contact_id: sd_contact.id, inbox_id: conversation.inbox_id)
    expect(command.result).to include('conversation_id' => conversation.display_id)
    get "/api/v1/accounts/#{sd_account.id}/conversations/#{conversation.display_id}/messages", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(input.dig('reply', 'content'))
    expect { approve_native(approval) }.not_to change(Message, :count)
    expect(response).to have_http_status(:ok)
    expect(a_request(:any, %r{https?://})).not_to have_been_made
  end

  it 'blocks the expired native WhatsApp window without preparing a command or offering a bypass' do
    conversation.messages.incoming.update_all(created_at: 25.hours.ago)
    expect(conversation.reload.can_reply?).to be(false)
    value = action_preview(input)
    action = value.fetch('actions').find { |row| row['tool'] == 'send_message' }
    expect(action).to include('can_prepare' => false, 'blocked_reason' => 'native_messaging_window_closed')
    post "#{base}/group_prepare", params: { event_id: event.id, group_key: selected_group, input: input, tool: action.fetch('tool'),
                                            arguments: action.fetch('arguments'), preview_digest: value.fetch('preview_digest') },
                                  headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcNico::Helpdesk::Approval.where(account: sd_account)).to be_empty
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'rechecks the native window after preparation and queues no public message when it closes' do
    approval = prepare_native(input, 'send_message')
    conversation.messages.incoming.update_all(created_at: 25.hours.ago)
    expect { approve_native(approval) }.not_to change(Message, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(approval.reload.state).to eq('pending')
  end

  it 'keeps bot-owned conversations under their existing bot and rejects native execution after a handoff change' do
    approval = prepare_native(input, 'send_message')
    bot = create(:agent_bot, account: sd_account)
    conversation.update!(assignee_agent_bot: bot)
    expect { approve_native(approval) }.not_to change(Message, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(approval.reload.state).to eq('pending')
    value = action_preview(input)
    expect(value.fetch('actions').find { |row| row['tool'] == 'send_message' })
      .to include('can_prepare' => false, 'blocked_reason' => 'native_bot_or_flow_owned')
    expect(conversation.reload.assignee_agent_bot_id).to eq(bot.id)
  end

  it 'rejects an unlinked conversation even when it belongs to the same visible customer and account' do
    other = create(:conversation, account: sd_account, inbox: conversation.inbox, contact: sd_contact)
    invalid = input.deep_merge('reply' => { 'conversation_id' => other.display_id })
    post "#{base}/group_preview", params: { event_id: event.id, group_key: selected_group, input: invalid }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(other.messages.outgoing).to be_empty
  end

  it 'blocks an inbox assigned to its native automation bot without taking over or queueing a reply' do
    binding = create(:agent_bot_inbox, account: sd_account, inbox: conversation.inbox, agent_bot: create(:agent_bot, account: sd_account))
    value = action_preview(input)
    expect(value.fetch('actions').find { |row| row['tool'] == 'send_message' })
      .to include('can_prepare' => false, 'blocked_reason' => 'native_bot_or_flow_owned')
    expect(binding.reload).to be_active
    expect(conversation.messages.outgoing).to be_empty
    expect(JrcNico::Helpdesk::Approval.where(account: sd_account)).to be_empty
  end

  it 'rejects a linked conversation whose customer differs from the ticket requester' do
    other = create(:conversation, account: sd_account, inbox: conversation.inbox, contact: create(:contact, account: sd_account))
    JrcServiceDesk::TicketConversation.create!(account: sd_account, unit: sd_unit, ticket: ticket,
                                               conversation: other, linked_by_membership: sd_membership)
    invalid = input.deep_merge('reply' => { 'conversation_id' => other.display_id })
    post "#{base}/group_preview", params: { event_id: event.id, group_key: selected_group, input: invalid }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(other.messages.outgoing).to be_empty
  end

  it 'rejects private and template fields instead of creating a parallel message/template flow' do
    %w[private template_params].each do |key|
      invalid = input.deep_merge('reply' => { key => key == 'private' ? true : { 'name' => 'fabricated' } })
      post "#{base}/group_preview", params: { event_id: event.id, group_key: selected_group, input: invalid }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(JrcNico::Helpdesk::Approval.where(account: sd_account)).to be_empty
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'hides the successful receipt after the current native conversation permission is revoked' do
    approval = prepare_native(input, 'send_message')
    approve_native(approval)
    approved_action(approval)
    permissions = %w[module_view tickets_view notes_view history_view sla_view customers_view]
    role = create(:custom_role, account: sd_account, permissions: permissions.map { |key| "jrc_service_desk_#{key}" })
    sd_account_user.update!(role: :agent, custom_role: role)
    verify_receipt_hidden(approval)
    expect(approval.reload.state).to eq('succeeded')
    expect(conversation.messages.outgoing.count).to eq(1)
  end

  context 'with an actual legal customer observation' do
    let(:selected_rule) { 'R11' }

    it 'cannot use acknowledgement to dispatch legal content outside the existing internal-only rule' do
      post "#{base}/group_preview", params: { event_id: event.id, group_key: 'D2', input: input }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(event.rule_key).to eq('R11')
      expect(conversation.messages.outgoing).to be_empty
    end
  end
end
