# frozen_string_literal: true

# Returning a route is not a substitute for the native conversation authorization on entry.
class JrcServiceDesk::ConversationNavigationService
  def initialize(user_context:, ticket:)
    @context = JrcServiceDesk::OperationalContext.new(user_context)
    @ticket = ticket
  end

  def call(link_id:)
    Pundit.authorize(@context.to_h, @ticket, :view_conversations?)
    link = @ticket.ticket_conversations.where(account_id: @context.account.id, unit_id: @ticket.unit_id)
      .find(JrcServiceDesk::Input.id(link_id))
    Pundit.authorize(@context.to_h, link, :show?)
    conversation = Conversation.where(account_id: @context.account.id).find(link.conversation_id)
    Pundit.authorize(@context.to_h, conversation, :show?)
    { contract_version: 1, account_id: @context.account.id.to_s, unit_id: @ticket.unit_id.to_s,
      ticket_id: @ticket.id.to_s, link_id: link.id.to_s, conversation_id: conversation.id.to_s,
      # The native route uses display_id, not the database primary key.
      conversation_display_id: conversation.display_id.to_s,
      route: { name: 'inbox_conversation', params: { accountId: @context.account.id.to_s, conversation_id: conversation.display_id.to_s } } }
  end
end
