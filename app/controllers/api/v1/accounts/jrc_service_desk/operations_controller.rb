# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::OperationsController < Api::V1::Accounts::JrcServiceDesk::BaseController
  # Require the explicit command envelope; do not auto-wrap native model fields.
  wrap_parameters false
  prepend_before_action :disable_response_cache
  before_action :require_operational_identity!
  around_action :consistent_reads
  after_action :disable_response_cache
  rescue_from ArgumentError, KeyError, ActionController::ParameterMissing, with: :bad_input
  rescue_from ActiveRecord::StaleObjectError, ::JrcServiceDesk::IdempotencyConflict, with: :write_conflict
  rescue_from ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey, ActiveRecord::NotNullViolation, with: :constraint_conflict

  private

  def require_operational_identity!
    context = ::JrcServiceDesk::OperationalContext.new(pundit_user)
    raise Pundit::NotAuthorizedError unless context.native_operator? && context.unit_scope.exists?
  end

  def consistent_reads
    if request.get? && !ActiveRecord::Base.connection.transaction_open?
      ActiveRecord::Base.transaction(isolation: :repeatable_read) { yield }
    else
      yield
    end
  end

  def disable_response_cache
    response.headers['Cache-Control'] = 'no-store'
  end

  def presenter
    @presenter ||= ::JrcServiceDesk::Presenter.new(user_context: pundit_user)
  end

  def base_payload
    { contract_version: 1, account_id: Current.account.id.to_s }
  end

  def query_values
    request.query_parameters
  end

  def body_values(allowed)
    ::JrcServiceDesk::Input.attributes(request.request_parameters, allowed)
  end

  def strict_ticket
    @strict_ticket ||= policy_scope(::JrcServiceDesk::Ticket).find(::JrcServiceDesk::Input.id(params[:id]))
  end

  def result_for(collection)
    base_payload.merge(items: collection[:items].map { |record| yield record }, meta: collection[:meta])
  end

  def acknowledged(ticket, operation, status: :ok, result_id: nil)
    render json: base_payload.merge(applied: true, ticket_id: ticket.id.to_s, operation: operation, result_id: result_id&.to_s), status: status
  end

  # The native around-handler delegates here for policy errors. Authentication
  # still uses the native 401; operational authorization is explicitly 403.
  def render_unauthorized(_message)
    response.headers['Cache-Control'] = 'no-store'
    render json: { error: 'Service Desk access denied', code: 'forbidden' }, status: :forbidden
  end

  def render_not_found_error(_message)
    render json: { error: 'Service Desk resource unavailable', code: 'not_found' }, status: :not_found
  end

  def bad_input(_error)
    render json: { error: 'Invalid or unsupported Service Desk input', code: 'invalid_input' }, status: :unprocessable_entity
  end

  def write_conflict(_error)
    render json: { error: 'Conflict: refresh the record or review the request key', code: 'conflict' }, status: :conflict
  end

  def constraint_conflict(_error)
    render json: { error: 'Related records changed or are outside the permitted scope', code: 'constraint_conflict' }, status: :conflict
  end

  def render_record_invalid(error)
    render json: { error: 'Record validation failed', code: 'validation_failed', fields: error.record.errors.attribute_names }, status: :unprocessable_entity
  end
end
