# frozen_string_literal: true

class JrcServiceDesk::LinkConversationService < JrcServiceDesk::BaseService
  def call(ticket_id:, conversation_id:)
    conversation_id = JrcServiceDesk::Input.id(conversation_id)
    with_ticket(ticket_id, :link_conversation?) do |ticket|
      conversation = Conversation.where(account_id: context.account.id).find(conversation_id)
      authorize!(conversation, :show?) # Native channel access is required independently.
      existing = JrcServiceDesk::TicketConversation.find_by(account_id: context.account.id, unit_id: ticket.unit_id,
                                                             ticket_id: ticket.id, conversation_id: conversation.id)
      next existing if existing

      link = JrcServiceDesk::TicketConversation.new(account: context.account, unit: ticket.unit, ticket: ticket,
                                                      conversation: conversation, linked_by_membership: actor_membership)
      authorize!(link, :create?)
      link.save!
      append_event!(ticket, 'conversation_linked', 'conversation_id' => conversation.id, 'link_id' => link.id)
      link
    end
  end
end
