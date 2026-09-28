# frozen_string_literal: true

class JrcServiceDesk::UpdateTicketService < JrcServiceDesk::BaseService
  FIELDS = %w[title description priority_id category_id].freeze

  def call(ticket_id:, attributes:, expected_lock_version:)
    values = JrcServiceDesk::Input.attributes(attributes, FIELDS)
    raise ArgumentError, 'No editable attributes' if values.empty?

    with_ticket(ticket_id, :show?) do |ticket|
      authorize!(ticket, :update?) if (values.keys - ['priority_id']).any?
      authorize!(ticket, :change_priority?) if values.key?('priority_id')
      verify_version!(ticket, expected_lock_version)
      ticket.title = text(values['title']) if values.key?('title')
      ticket.description = text(values['description'], nullable: true) if values.key?('description')
      ticket.priority = reference(JrcServiceDesk::Priority, values['priority_id'], ticket.unit) if values.key?('priority_id')
      ticket.category = reference(JrcServiceDesk::Category, values['category_id'], ticket.unit) if values.key?('category_id')
      next ticket unless ticket.changed?

      ticket.save!
      append_event!(ticket, 'ticket_updated', ticket.saved_changes.slice(*FIELDS))
      ticket
    end
  end
end
