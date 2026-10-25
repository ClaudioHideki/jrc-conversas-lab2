# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::AutomationPublicationsController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def index
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id kind q active page per_page])
    authorize ::JrcServiceDesk::AutomationPublication, :index?
    unit = context.unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    raise ArgumentError unless %w[lifecycle operational].include?(values['kind'])

    scope = policy_scope(::JrcServiceDesk::AutomationPublication).where(unit: unit, kind: values['kind'])
    # Latest immutable receipt for every code; metrics derive from these rows.
    query = ::JrcServiceDesk::QueryParameters.new(values.except('kind', 'active'), catalog: true)
    raise ArgumentError unless %w[all true false].include?(values.fetch('active', 'all'))

    rows = scope.where(id: scope.group(:code).select('MAX(id)')).order(:name).select { |row| ::JrcServiceDesk::AutomationPublicationPolicy.new(pundit_user, row).show? }
    counts = { total: rows.size, enabled: rows.count(&:enabled?), disabled: rows.count { |row| !row.enabled? } }
    rows = rows.select { |row| [row.name, row.code, row.description].join(' ').downcase.include?(query['q'].to_s.downcase) }
    rows = rows.select { |row| row.enabled? == (values['active'] == 'true') } if %w[true false].include?(values['active'])
    render json: base_payload.merge(unit_id: unit.id.to_s, items: (rows.slice(query.offset, query.per_page) || []).map { |row| projection(row) }, total: rows.size, counts: counts)
  end

  def show
    row = policy_scope(::JrcServiceDesk::AutomationPublication).find(::JrcServiceDesk::Input.id(params[:id]))
    authorize row, :show?
    render json: base_payload.merge(unit_id: row.unit_id.to_s, publication: projection(row))
  end

  def options
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id kind service_id])
    unit = context.unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    raise ArgumentError unless %w[lifecycle operational].include?(values['kind'])
    authorize ::JrcServiceDesk::AutomationPublication.new(account: Current.account, unit: unit, kind: values.fetch('kind')), :create?
    inboxes = ::JrcServiceDesk::NativeExecutionContext.with(context.to_h) do
      context.account.inboxes.order(:name).filter_map do |row|
        { id: row.id, name: row.name, channel_type: row.channel_type } if Pundit.policy!(pundit_user, row).show?
      end
    end
    labels = Pundit.policy!(pundit_user, Label).index? ? context.account.labels.map { |row| { id: row.id, name: row.title } } : []
    statuses = Pundit.policy_scope!(pundit_user, ::JrcServiceDesk::TicketStatus).where(unit: unit, active: true).order(:position, :id)
      .filter_map { |row| { id: row.id, name: row.name, phase: row.phase } if Pundit.policy!(pundit_user, row).show? }
    service = ::JrcServiceDesk::Service.where(account: context.account, unit: unit).find(::JrcServiceDesk::Input.id(values['service_id'])) if values['service_id']
    authorize service, :show? if service
    render json: base_payload.merge(unit_id: unit.id.to_s, inboxes: inboxes, labels: labels, statuses: statuses,
                                    service_id: service&.id&.to_s, service_name: service&.name, form_fields: service&.form_fields || [])
  end

  def preview
    values = body_values(%w[unit_id attributes facts at])
    unit = context.unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    composition = ::JrcServiceDesk::AutomationComposition.new(values.fetch('attributes'))
    authorize ::JrcServiceDesk::AutomationPublication.new(account: Current.account, unit: unit, kind: composition.values.fetch('kind')), :create?
    result = ::JrcServiceDesk::AutomationPublicationService.new(user_context: pundit_user).preview(**values.symbolize_keys)
    render json: base_payload.merge(unit_id: values.fetch('unit_id').to_s, preview: result)
  end

  def create
    values = body_values(%w[unit_id attributes expected_version expected_native_versions confirmed idempotency_key])
    result = ::JrcServiceDesk::AutomationPublicationService.new(user_context: pundit_user).call(**values.symbolize_keys)
    row = result.publication
    render json: base_payload.merge(unit_id: row.unit_id.to_s, publication: projection(row), audit_id: result.audit_id.to_s), status: :created
  end

  private

  def context
    ::JrcServiceDesk::OperationalContext.new(pundit_user)
  end

  def projection(row)
    authorize row, :show?
    row.attributes.slice('kind', 'code', 'name', 'description', 'service_id', 'version', 'enabled', 'definition', 'native_versions', 'digest').merge(
      'id' => row.id.to_s, 'unit_id' => row.unit_id.to_s, 'account_id' => row.account_id.to_s, 'created_at' => row.created_at.iso8601(6))
  end
end
