# frozen_string_literal: true

class JrcServiceDesk::FindTicketService < JrcServiceDesk::BaseService
  def call(ticket_id:)
    @context = fresh_context!
    record = JrcServiceDesk::TicketPolicy::Scope.new(context.to_h, JrcServiceDesk::Ticket).resolve.find(JrcServiceDesk::Input.id(ticket_id))
    authorize!(record, :show?)
    record
  end
end
