class Api::V1::Accounts::Approvals::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_core_enabled
  rescue_from JrcApprovals::Error do |error|
    conflicts = %w[VERSION_CONFLICT IDEMPOTENCY_CONTENT_CONFLICT POLICY_SELECTION_CONFLICT ALREADY_VOTED CONTEXT_STALE]
    render json: { error: error.code }, status: conflicts.include?(error.code) ? :conflict : :unprocessable_entity
  end
  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: { errors: error.record.errors.full_messages }, status: :unprocessable_entity
  end
  rescue_from ActiveRecord::StaleObjectError do
    render json: { error: 'VERSION_CONFLICT' }, status: :conflict
  end
  rescue_from ArgumentError, KeyError do
    render json: { error: 'INVALID_INPUT' }, status: :unprocessable_entity
  end

  private

  def ensure_core_enabled
    authorization.member!
  end

  def authorization
    JrcApprovals::Authorization.new(account: Current.account, user: Current.user)
  end

  def service(type)
    type.new(account: Current.account, user: Current.user)
  end

  def request_payload(record)
    JrcApprovals::RequestSerializer.new(record).as_json
  end

  def readable_request
    record = JrcApprovals::Request.where(account_id: Current.account.id).find(params[:id])
    JrcApprovals::RequestVisibility.authorize!(account: Current.account, user: Current.user, record: record)
    record
  end

  def filtered(relation, fields)
    fields.each { |field| relation = relation.where(field => params[field]) if params[field].present? }
    relation
  end

  def paginated(rows)
    page = params[:page].present? ? Integer(params[:page].to_s, 10) : 1
    limit = params[:per_page].present? ? Integer(params[:per_page].to_s, 10) : 25
    raise JrcApprovals::Error, 'INVALID_PAGINATION' unless page.positive? && limit.between?(1, 100)

    response.set_header('X-Total-Count', rows.length.to_s)
    response.set_header('X-Page', page.to_s)
    response.set_header('X-Per-Page', limit.to_s)
    rows.slice((page - 1) * limit, limit) || []
  end
end
