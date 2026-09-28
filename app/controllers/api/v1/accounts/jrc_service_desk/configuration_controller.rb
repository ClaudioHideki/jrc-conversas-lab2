# frozen_string_literal: true

# Closed resource whitelist; only the five already-authorized unit catalogues.
class Api::V1::Accounts::JrcServiceDesk::ConfigurationController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def index
    authorize resource_model, :manage_index?
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id q page per_page active])
    unit = policy_scope(::JrcServiceDesk::Unit).find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize resource_model.new(account: Current.account, unit: unit), :update?
    active = values.delete('active') || 'all'
    raise ArgumentError unless %w[all true false].include?(active)
    query = ::JrcServiceDesk::QueryParameters.new(values, catalog: true)
    records = policy_scope(resource_model).where(account_id: Current.account.id, unit_id: unit.id)
    records = records.where(active: active == 'true') unless active == 'all'
    records = records.where('name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(query['q'])}%") if query['q'].present?
    render json: base_payload.merge(resource: resource, unit_id: unit.id.to_s,
      items: records.order(:name, :id).offset(query.offset).limit(query.per_page).map { |r| project(r) },
      meta: { total: records.count, page: query.page, per_page: query.per_page })
  end

  def show
    raise ArgumentError unless query_values.empty?
    authorize configuration_record, :update?
    render json: base_payload.merge(resource: resource, record: project(configuration_record))
  end

  def create
    values = body_values(%w[unit_id record])
    unit = policy_scope(::JrcServiceDesk::Unit).find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize resource_model.new(account: Current.account, unit: unit), :create?
    result = command.create(resource: resource, unit_id: unit.id, attributes: values.fetch('record'), idempotency_key: request.headers['Idempotency-Key'])
    render_result(result, :created)
  end

  def update
    authorize configuration_record, :update?
    values = body_values(%w[record expected_revision])
    result = command.update(resource: resource, record_id: configuration_record.id, attributes: values.fetch('record'),
      expected_revision: values.fetch('expected_revision'), idempotency_key: request.headers['Idempotency-Key'])
    render_result(result, :ok)
  end

  def receipt
    raise ArgumentError unless query_values.empty?
    authorize configuration_record, :update?
    context = ::JrcServiceDesk::OperationalContext.new(pundit_user)
    membership = context.active_memberships.where(unit_id: configuration_record.unit_id).take!
    audit = ::JrcServiceDesk::ConfigurationAudit.new(context: context, membership: membership)
    render json: base_payload.merge(receipt: audit.receipt(resource, configuration_record, params[:audit_id]))
  end

  private

  def resource
    params[:resource].to_s
  end

  def resource_model
    ::JrcServiceDesk::ConfigurationResources.model(resource)
  end

  def configuration_record
    @configuration_record ||= policy_scope(resource_model).find(::JrcServiceDesk::Input.id(params[:id]))
  end

  def project(record)
    authorize record, :update?
    ::JrcServiceDesk::ConfigurationResources.project(resource, record)
  end

  def command
    ::JrcServiceDesk::ConfigurationService.new(user_context: pundit_user)
  end

  def render_result(result, status)
    render json: base_payload.merge(resource: resource, record: project(result.record), audit_id: result.audit_id.to_s), status: status
  end
end
