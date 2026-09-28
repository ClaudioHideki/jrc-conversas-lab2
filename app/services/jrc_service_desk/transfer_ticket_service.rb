# frozen_string_literal: true

# Same-unit reassignment only; distinct capability and audit event.
class JrcServiceDesk::TransferTicketService < JrcServiceDesk::AssignTicketService
  def call(ticket_id:, attributes:, expected_lock_version:)
    apply_assignment(ticket_id: ticket_id, attributes: attributes, expected_lock_version: expected_lock_version,
                     query: :transfer?, event_type: 'ticket_transferred')
  end
end
