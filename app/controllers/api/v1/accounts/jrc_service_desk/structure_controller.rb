# frozen_string_literal: true

# Inherits native authentication/Account helper and CP1 feature gate, NOT an operational bypass.
class Api::V1::Accounts::JrcServiceDesk::StructureController < Api::V1::Accounts::JrcServiceDesk::BaseController
  wrap_parameters false
  prepend_before_action :no_cache
  before_action :require_structure!
  rescue_from ArgumentError, KeyError, ActionController::ParameterMissing, with: :bad_input
  rescue_from ActiveRecord::StaleObjectError, ::JrcServiceDesk::IdempotencyConflict, ActiveRecord::RecordNotUnique, with: :conflict

  def context
    authorize Current.account, :context?, policy_class: ::JrcServiceDesk::StructurePolicy
    render json: envelope.merge(user_id: Current.user.id.to_s, account_user_id: Current.account_user.id.to_s, available: true,
      capabilities: ::JrcServiceDesk::StructureContract::RESOURCES.to_h { |r| [r, structural.allowed?(r)] })
  end

  def index
    authorize model, :index?, policy_class: ::JrcServiceDesk::StructurePolicy
    values = ::JrcServiceDesk::Input.attributes(request.query_parameters, %w[page q])
    page = ::JrcServiceDesk::Input.id(values.fetch('page', 1))
    raise ArgumentError if page > 1_000_000
    query = values.fetch('q', '')
    raise ArgumentError unless query.is_a?(String) && query.length <= 200
    records = policy_scope(model, policy_scope_class: ::JrcServiceDesk::StructurePolicy::Scope)
    if resource != 'unit_memberships' && !query.empty?
      records = records.where('name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
    end
    render json: envelope.merge(resource: resource, items: records.order(:id).offset((page - 1) * 25).limit(25).map { |r| project(r) },
      meta: { page: page, per_page: 25, total: records.count })
  end

  def show
    authorize record, :show?, policy_class: ::JrcServiceDesk::StructurePolicy
    render json: envelope.merge(resource: resource, record: project(record))
  end

  def members
    authorize Current.account, :members?, policy_class: ::JrcServiceDesk::StructurePolicy
    values = ::JrcServiceDesk::Input.attributes(request.query_parameters, %w[page q unit_id])
    page = ::JrcServiceDesk::Input.id(values.fetch('page', 1))
    query = values.fetch('q', '')
    raise ArgumentError unless page <= 1_000_000 && query.is_a?(String) && query.length <= 200
    rows = AccountUser.where(account_id: Current.account.id).joins(:user).where(users: { type: [nil, ''] })
      .where.not(users: { confirmed_at: nil }).where.not(user_id: ::JrcServiceDesk::InitializerAuthority.ids)
    rows = rows.where('users.name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(query)}%") unless query.blank?
    unit = if values.key?('unit_id')
             policy_scope(::JrcServiceDesk::Unit, policy_scope_class: ::JrcServiceDesk::StructurePolicy::Scope)
               .find(::JrcServiceDesk::Input.id(values['unit_id']))
           end
    members = rows.order(:id).limit(25).offset((page - 1) * 25).includes(:user).to_a
    data = ::JrcServiceDesk::MembershipDirectory.new(account: Current.account, unit: unit).project(members)
    render json: envelope.merge(data).merge(meta: { page: page, per_page: 25, total: rows.count })
  end

  def create
    authorize model.new(account: Current.account), :create?, policy_class: ::JrcServiceDesk::StructurePolicy
    values = body(%w[record reason])
    result = command.create(resource: resource, attributes: values.fetch('record'), reason: values.fetch('reason'),
      idempotency_key: request.headers['Idempotency-Key'])
    render_result(result, :created)
  end

  def update
    authorize record, :update?, policy_class: ::JrcServiceDesk::StructurePolicy
    values = body(%w[record reason expected_revision])
    result = command.update(resource: resource, record_id: record.id, attributes: values.fetch('record'), reason: values.fetch('reason'),
      expected_revision: values.fetch('expected_revision'), idempotency_key: request.headers['Idempotency-Key'])
    render_result(result, :ok)
  end

  def receipt
    authorize record, :receipt?, policy_class: ::JrcServiceDesk::StructurePolicy
    audit = ::JrcServiceDesk::StructureAudit.new(account: Current.account, actor: Current.user, account_user: Current.account_user)
    render json: envelope.merge(receipt: audit.receipt(resource, record, params[:audit_id]))
  end

  private

  def no_cache
    response.headers['Cache-Control'] = 'no-store'
  end

  def structural
    ::JrcServiceDesk::StructureContext.new(pundit_user)
  end

  def require_structure!
    raise Pundit::NotAuthorizedError unless structural.available?
  end

  def resource
    params[:resource].to_s
  end

  def model
    ::JrcServiceDesk::StructureRecords.model(resource)
  end

  def record
    @record ||= policy_scope(model, policy_scope_class: ::JrcServiceDesk::StructurePolicy::Scope).find(::JrcServiceDesk::Input.id(params[:id]))
  end

  def project(value)
    ::JrcServiceDesk::StructureRecords.project(resource, value)
  end

  def envelope
    { contract_version: 1, account_id: Current.account.id.to_s }
  end

  def body(allowed)
    ::JrcServiceDesk::Input.attributes(request.request_parameters, allowed)
  end

  def command
    ::JrcServiceDesk::StructureService.new(user_context: pundit_user)
  end

  def render_result(result, status)
    render json: envelope.merge(resource: resource, record: project(result.record), audit_id: result.audit_id.to_s), status: status
  end

  def render_unauthorized(_message)
    render json: { code: 'forbidden', error: 'Structural authority required' }, status: :forbidden
  end

  def render_not_found_error(_message)
    render json: { code: 'not_found', error: 'Record unavailable' }, status: :not_found
  end

  def bad_input(_error)
    render json: { code: 'invalid_input', error: 'Invalid structural request' }, status: :unprocessable_entity
  end

  def conflict(_error)
    render json: { code: 'conflict', error: 'Refresh the record or recover the same request' }, status: :conflict
  end
end
