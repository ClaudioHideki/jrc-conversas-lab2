# frozen_string_literal: true

# Read-only template checks inside the existing locked rule command. Customer,
# original agent and all native effects are reauthorized by the real executor.
class JrcContactCenter::EndingActions::ServiceDeskRuleParameters < JrcServiceDesk::BaseService
  REFERENCES = { 'status_id' => JrcServiceDesk::TicketStatus, 'priority_id' => JrcServiceDesk::Priority,
                 'category_id' => JrcServiceDesk::Category, 'queue_id' => JrcServiceDesk::Queue,
                 'ticket_type_id' => JrcServiceDesk::TicketType, 'subcategory_id' => JrcServiceDesk::Category }.freeze

  def initialize(user_context:, source_scope:)
    super(user_context: user_context)
    @source_scope = source_scope
  end

  def call(value)
    ensure_transaction!

    input = JrcContactCenter::EndingActions::ServiceDeskDestinationDefinition.new.call(value)
    @context = fresh_context!
    unit = context.unit_scope.lock('FOR SHARE').find(input.fetch('unit_id'))
    authorize_mapping!(unit)
    authorize_configuration!(unit, input)
    input
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition'
  end

  def source_configuration
    ensure_transaction!
    mapped_configuration
  end

  private

  def ensure_transaction!
    raise JrcContactCenter::OperationError, 'ending_destination_requires_transaction' unless Account.connection.transaction_open?
  end

  def mapped_configuration
    @context = fresh_context!
    business = context.account.jrc_crm_business_units.where(active: true).find(@source_scope.fetch('business_unit_id'))
    identifier = JrcServiceDesk::Input.id(business.settings.fetch('service_desk_unit_id', nil))
    unit = context.unit_scope.lock('FOR SHARE').find(identifier)
    authorize_mapping!(unit)
    raise Pundit::NotAuthorizedError unless context.capability?(:tickets_create) && context.capability?(:customers_view)

    authorize!(JrcServiceDesk::Ticket.new(account: context.account, unit: unit), :create?)
    JrcServiceDesk::CatalogueForm.new(user_context: context.to_h).call(parameters: { 'unit_id' => unit.id.to_s })
    { configuration_available: true, unit: { id: unit.id.to_s, name: unit.name } }
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError, JrcContactCenter::OperationError, ArgumentError
    { configuration_available: false }
  end

  def authorize_mapping!(unit)
    raise JrcContactCenter::OperationError, 'ending_service_desk_mapping_required' unless @source_scope['business_unit_id']

    business = context.account.jrc_crm_business_units.where(active: true).lock('FOR SHARE').find(@source_scope.fetch('business_unit_id'))
    linked = JrcServiceDesk::Input.id(business.settings.fetch('service_desk_unit_id', nil))
    expected = [@source_scope.fetch('issuer_company_id').to_s, unit.id]
    return if [business.company_id.to_s, linked] == expected

    raise JrcContactCenter::OperationError.new('ending_service_desk_mapping_changed', status: :conflict)
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'ending_service_desk_mapping_required'
  end

  def authorize_configuration!(unit, input)
    raise Pundit::NotAuthorizedError unless context.capability?(:tickets_create) && context.capability?(:customers_view)

    fields = input.fetch('attributes')
    validate_text!(fields)
    form = catalogue_form(unit, input)
    JrcServiceDesk::CatalogueAnswers.new(form.fetch(:form_fields)).validate!(fields.fetch('service_fields', {}))
    candidate = native_candidate(unit, fields, form)
    authorize!(candidate, :create?)
    verify_assignee_team!(candidate)
    authorize_contract!(fields['contract_id'])
  end

  def catalogue_form(unit, input)
    service = reference(JrcServiceDesk::Service, input.fetch('service_id'), unit)
    authorize!(service, :show?) if service
    raise Pundit::NotAuthorizedError if service&.default_assignee_membership && !context.capability?(:tickets_assign)

    selection = input.fetch('attributes').slice('ticket_type_id', 'category_id', 'subcategory_id')
    selection.merge!('unit_id' => unit.id.to_s, 'service_id' => input.fetch('service_id'))
    JrcServiceDesk::CatalogueForm.new(user_context: context.to_h).call(parameters: selection)
  end

  def native_candidate(unit, fields, form)
    references = native_references(unit, fields, form)
    candidate = JrcServiceDesk::Ticket.new(account: context.account, unit: unit, **references)
    validate_initial_status!(candidate.status)
    raise JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition' unless candidate.priority

    candidate.team = native_team(fields['team_id'] || candidate.queue&.team_id)
    candidate.assignee_membership = assignee(fields['assignee_account_user_id'], unit)
    assigned = candidate.queue || candidate.team || candidate.assignee_membership || form.dig(:defaults, :assignee_account_user_id)
    raise Pundit::NotAuthorizedError if assigned && !context.capability?(:tickets_assign)

    candidate
  end

  def native_references(unit, fields, form)
    values = fields.dup
    values['priority_id'] ||= form.dig(:defaults, :priority_id)
    values['queue_id'] ||= form.dig(:defaults, :queue_id)
    REFERENCES.to_h do |key, model|
      record = reference(model, values[key], unit)
      authorize!(record, :show?) if record
      [key.delete_suffix('_id').to_sym, record]
    end
  end

  def authorize_contract!(identifier)
    return if identifier.nil?

    # Customer/contract association is deliberately checked again against the
    # original attendance by the native Ticket workflow, never by a supplied ID.
    JrcServiceDesk::CatalogueContracts.new(context).scope.find(JrcServiceDesk::Input.id(identifier))
  end

  def validate_initial_status!(status)
    return if status&.initial? && status.active? && status.phase == 'open'

    raise JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition'
  end

  def validate_text!(fields)
    valid = fields.fetch('title').length <= 255 && fields['description'].is_a?(String) && fields.fetch('description').strip.present?
    raise JrcContactCenter::OperationError, 'invalid_ending_service_desk_definition' unless valid
  end
end
