# frozen_string_literal: true

class JrcServiceDesk::CatalogueForm
  def initialize(user_context:)
    @context = JrcServiceDesk::OperationalContext.new(user_context)
  end

  def call(parameters:)
    values = JrcServiceDesk::Input.attributes(parameters, %w[unit_id service_id ticket_type_id category_id subcategory_id])
    Pundit.authorize(@context.to_h, :lookup, :index?, policy_class: JrcServiceDesk::LookupPolicy)
    unit = @context.unit_scope.find(JrcServiceDesk::Input.id(values.fetch('unit_id')))
    records = selected_records(values, unit)
    payload = definition_payload(unit, records).merge(restrictions(records.first))
    payload.merge(revision: JrcServiceDesk::CanonicalJson.digest(payload))
  end

  private

  def selected_records(values, unit)
    service = reference(JrcServiceDesk::Service, values['service_id'], unit)
    type_id = selected_id(values, 'ticket_type_id', service&.default_ticket_type_id)
    category_id = selected_id(values, 'category_id', service&.default_category_id)
    type = reference(JrcServiceDesk::TicketType, type_id, unit)
    category = reference(JrcServiceDesk::Category, category_id, unit)
    subcategory = reference(JrcServiceDesk::Category, values['subcategory_id'], unit)
    validate_subcategory!(category, subcategory)

    [service, type, category, subcategory]
  end

  def selected_id(values, key, default)
    values.key?(key) ? values[key] : default
  end

  def validate_subcategory!(category, subcategory)
    return unless subcategory

    raise ArgumentError, 'Subcategory does not belong to category' unless subcategory.parent_id == category&.id
  end

  def form_fields(records)
    fields = records.compact.flat_map(&:form_fields)
    definition = JrcServiceDesk::CatalogueFields.new(fields)
    raise ArgumentError, 'Conflicting catalogue fields' unless definition.valid? && !definition.duplicate_keys?

    fields
  end

  def definition_payload(unit, records)
    service, type, category, subcategory = records
    { contract_version: 1, account_id: @context.account.id.to_s, unit_id: unit.id.to_s, form_fields: form_fields(records),
      service: named(service), ticket_type: named(type), category: named(category), subcategory: named(subcategory),
      service_revision: service && JrcServiceDesk::ConfigurationResources.revision('services', service), defaults: defaults(service) }
  end

  def restrictions(service)
    return { allowed_company_ids: [], allowed_contract_ids: [] } unless @context.capability?(:customers_view) && service

    { allowed_company_ids: service.allowed_company_ids.map(&:to_s), allowed_contract_ids: service.allowed_contract_ids.map(&:to_s) }
  end

  def reference(model, id, unit)
    return nil if id.nil? || id == ''

    record = model.where(account_id: @context.account.id, unit_id: unit.id, active: true).find(JrcServiceDesk::Input.id(id))
    Pundit.authorize(@context.to_h, record, :show?)
    record
  end

  def defaults(service)
    member = service&.default_assignee_membership
    allowed = member && @context.capability?(:tickets_assign)
    { priority_id: service&.default_priority_id&.to_s, queue_id: service&.default_queue_id&.to_s,
      assignee_account_user_id: allowed ? member.account_user_id.to_s : nil,
      priority: named(service&.default_priority), queue: named(service&.default_queue),
      assignee: allowed ? { id: member.account_user_id.to_s, name: member.account_user.user.name } : nil }
  end

  def named(record)
    record && { id: record.id.to_s, name: record.name.to_s }
  end
end
