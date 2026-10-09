# frozen_string_literal: true

class JrcServiceDesk::UpdateTicketService < JrcServiceDesk::BaseService
  FIELDS = %w[title description priority_id category_id ticket_type_id subcategory_id contract_id service_fields].freeze

  def call(ticket_id:, attributes:, expected_lock_version:, execution_command: nil)
    with_ticket(ticket_id, :show?) do |ticket|
      values = editable_values(attributes)
      authorize_update!(ticket, values)
      verify_version!(ticket, expected_lock_version)
      origin = JrcServiceDesk::NativeMutationOrigin.new(context: context, ticket: ticket, tool: 'update_service_ticket',
                                                        attributes: values, command: execution_command)
                                                   .call(expected_lock_version: expected_lock_version)
      apply_values(ticket, values)
      next ticket unless ticket.changed?

      ticket.save!
      append_event!(ticket, 'ticket_updated', ticket.saved_changes.slice(*editable_fields).merge('origin' => origin))
      ticket
    end
  end

  private

  def editable_fields
    context.account.feature_enabled?('jrc_customer_master') ? FIELDS + ['company_id'] : FIELDS
  end

  def editable_values(attributes)
    values = JrcServiceDesk::Input.attributes(attributes, editable_fields)
    raise ArgumentError, 'No editable attributes' if values.empty?

    values
  end

  def authorize_update!(ticket, values)
    authorize!(ticket, :update?) if (values.keys - ['priority_id']).any?
    authorize!(ticket, :change_priority?) if values.key?('priority_id')
    authorize!(ticket, :view_customer?) if values.keys.intersect?(%w[contract_id service_fields])
    return unless values.key?('contract_id') && ticket.contract_id
    return if JrcServiceDesk::CatalogueContracts.new(context).scope.exists?(id: ticket.contract_id)

    raise Pundit::NotAuthorizedError
  end

  def apply_values(ticket, values)
    apply_text_values(ticket, values)
    ticket.priority = reference(JrcServiceDesk::Priority, values['priority_id'], ticket.unit) if values.key?('priority_id')
    ticket.category = reference(JrcServiceDesk::Category, values['category_id'], ticket.unit) if values.key?('category_id')
    apply_company(ticket, values['company_id']) if values.key?('company_id')
    bind_catalogue(ticket, values) if values.keys.intersect?(%w[ticket_type_id subcategory_id contract_id category_id company_id])
    ticket.service_fields = values['service_fields'] if values.key?('service_fields')
  end

  def apply_text_values(ticket, values)
    ticket.title = text(values['title']) if values.key?('title')
    ticket.description = text(values['description'], nullable: true) if values.key?('description')
  end

  def apply_company(ticket, value)
    authorize!(ticket, :view_customer?)
    Pundit.authorize(context.to_h, :directory, :access?, policy_class: JrcCustomers::DirectoryPolicy)
    ticket.company_id = value.nil? ? nil : JrcServiceDesk::Input.id(value)
    JrcCustomers::Company.where(account_id: context.account.id).find(ticket.company_id) if ticket.company_id
  end

  def bind_catalogue(ticket, values)
    fields = %w[ticket_type_id subcategory_id contract_id]
    selected = ticket.attributes.slice(*fields).merge(values.slice(*fields))
    JrcServiceDesk::TicketCatalogue.new(ticket, context: context).bind!(selected)
  end
end
