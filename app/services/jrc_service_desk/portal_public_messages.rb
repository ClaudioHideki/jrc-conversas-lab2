# frozen_string_literal: true

# Public native agent replies are read from Message. Internal/private replies and
# ambiguous messages in conversations linked to several tickets stay private.
class JrcServiceDesk::PortalPublicMessages
  def initialize(scope:, ticket:)
    @scope, @ticket = scope, ticket
  end

  def messages
    conversation_ids = @scope.conversations.where(id: @ticket.ticket_conversations.select(:conversation_id)).select(:id)
    relation = Message.where(account_id: @ticket.account_id, conversation_id: conversation_ids, private: false, message_type: :outgoing)
    relation.order(created_at: :desc, id: :desc).limit(100).select do |message|
      marker = message.content_attributes['service_desk_ticket_id'].to_s
      marker == @ticket.id.to_s || (marker.blank? && JrcServiceDesk::TicketConversation.where(
        account_id: @ticket.account_id, conversation_id: message.conversation_id
      ).count == 1)
    end.reverse
  end

  def timeline
    delivered_notes = JrcServiceDesk::NotificationDelivery.where(account_id: @ticket.account_id, ticket_id: @ticket.id)
                                                       .where.not(ticket_note_id: nil).pluck(:message_id)
    messages.reject { |message| delivered_notes.include?(message.id) }
  end
end
