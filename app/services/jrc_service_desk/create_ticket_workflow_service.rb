# frozen_string_literal: true

# Atomic creation plus optional native conversation link, reusing the CP2 commands.
# Request context is recorded once to bind the optional relation to the same key.
class JrcServiceDesk::CreateTicketWorkflowService < JrcServiceDesk::BaseService
  def call(unit_id:, attributes:, idempotency_key:, conversation_id: nil, service_id: nil)
    conversation_id = JrcServiceDesk::Input.id(conversation_id) unless conversation_id.nil?
    service_id = JrcServiceDesk::Input.id(service_id) unless service_id.nil?
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    with_unit(unit_id) do |unit|
      raise Pundit::NotAuthorizedError unless context.capability?(:tickets_create)
      if conversation_id
        raise Pundit::NotAuthorizedError unless context.capability?(:conversations_link)
        conversation = Conversation.where(account_id: context.account.id).find(conversation_id)
        authorize!(conversation, :show?) # Includes replay; a saved key is not a grant.
      end
      existing = JrcServiceDesk::Ticket.find_by(account_id: context.account.id, unit_id: unit.id,
                                                 created_by_membership_id: actor_membership.id, idempotency_key: key)
      if existing
        authorize!(existing, :show?)
        marker = existing.ticket_events.find_by(event_type: 'creation_context_recorded')
        previous = marker&.data&.fetch('conversation_id', nil)
        raise JrcServiceDesk::IdempotencyConflict, 'Creation relation differs from original request' unless previous == conversation_id && existing.service_id == service_id
      end
      ticket = JrcServiceDesk::CreateTicketService.new(user_context: context.to_h).call(
        unit_id: unit.id, attributes: attributes, idempotency_key: key, service_id: service_id)
      unless existing
        if conversation_id
          JrcServiceDesk::LinkConversationService.new(user_context: context.to_h).call(ticket_id: ticket.id, conversation_id: conversation_id)
        end
        append_event!(ticket, 'creation_context_recorded', 'conversation_id' => conversation_id)
      end
      ticket
    end
  end
end
