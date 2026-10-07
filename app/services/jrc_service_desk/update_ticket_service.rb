# frozen_string_literal: true

class JrcServiceDesk::UpdateTicketService < JrcServiceDesk::BaseService
  FIELDS = %w[title description priority_id category_id].freeze

  def call(ticket_id:, attributes:, expected_lock_version:)
    with_ticket(ticket_id, :show?) do |ticket|
      fields = context.account.feature_enabled?('jrc_customer_master') ? FIELDS + ['company_id'] : FIELDS
      values = JrcServiceDesk::Input.attributes(attributes, fields)
      raise ArgumentError, 'No editable attributes' if values.empty?

      authorize!(ticket, :update?) if (values.keys - ['priority_id']).any?
      authorize!(ticket, :change_priority?) if values.key?('priority_id')
      verify_version!(ticket, expected_lock_version)
      ticket.title = text(values['title']) if values.key?('title')
      ticket.description = text(values['description'], nullable: true) if values.key?('description')
      ticket.priority = reference(JrcServiceDesk::Priority, values['priority_id'], ticket.unit) if values.key?('priority_id')
      ticket.category = reference(JrcServiceDesk::Category, values['category_id'], ticket.unit) if values.key?('category_id')
      if values.key?('company_id')
        authorize!(ticket, :view_customer?)
        Pundit.authorize(context.to_h, :directory, :access?, policy_class: JrcCustomers::DirectoryPolicy)
        ticket.company_id = values['company_id'].nil? ? nil : JrcServiceDesk::Input.id(values['company_id'])
        JrcCustomers::Company.where(account_id: context.account.id).find(ticket.company_id) if ticket.company_id
      end
      next ticket unless ticket.changed?

      ticket.save!
      append_event!(ticket, 'ticket_updated', ticket.saved_changes.slice(*fields))
      ticket
    end
  end
end
