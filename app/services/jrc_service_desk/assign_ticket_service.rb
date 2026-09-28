# frozen_string_literal: true

class JrcServiceDesk::AssignTicketService < JrcServiceDesk::BaseService
  FIELDS = %w[assignee_account_user_id queue_id team_id].freeze

  def call(ticket_id:, attributes:, expected_lock_version:)
    apply_assignment(ticket_id: ticket_id, attributes: attributes, expected_lock_version: expected_lock_version,
                     query: :assign?, event_type: 'ticket_assigned')
  end

  protected

  def apply_assignment(ticket_id:, attributes:, expected_lock_version:, query:, event_type:)
    values = JrcServiceDesk::Input.attributes(attributes, FIELDS)
    raise ArgumentError, 'No assignment attributes' if values.empty?

    with_ticket(ticket_id, query) do |ticket|
      verify_version!(ticket, expected_lock_version)
      if values.key?('queue_id')
        ticket.queue = reference(JrcServiceDesk::Queue, values['queue_id'], ticket.unit)
        ticket.team = native_team(ticket.queue&.team_id) unless values.key?('team_id')
      end
      ticket.team = native_team(values['team_id']) if values.key?('team_id')
      ticket.assignee_membership = assignee(values['assignee_account_user_id'], ticket.unit) if values.key?('assignee_account_user_id')
      next ticket unless ticket.changed?

      ticket.save!
      append_event!(ticket, event_type, ticket.saved_changes.slice('assignee_membership_id', 'queue_id', 'team_id'))
      ticket
    end
  end
end
