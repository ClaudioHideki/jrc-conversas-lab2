# frozen_string_literal: true

# First agent response only: the existing recorder verifies delivery evidence.
# A note, assignment, closure or incoming customer message is not that event.
class JrcRelationship::SurveyResponseEventJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = JrcServiceDesk::TicketEvent.find_by(id: event_id, event_type: 'first_response_observed')
    return unless event
    ticket = event.ticket
    reopening = ticket.lifecycle_transitions.where(action: 'reopen').order(:id).last
    return if reopening && reopening.occurred_at > event.created_at
    JrcRelationship::SurveyEngine.evaluate_event(
      source: ticket, event: 'first_agent_response',
      cycle_key: "service-desk:ticket:#{ticket.id}:cycle:#{reopening&.id || 'initial'}"
    )
  end
end
