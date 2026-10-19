class Api::V1::Accounts::JrcHistoryImportsController < Api::V1::Accounts::BaseController
  wrap_parameters false
  before_action :require_service_user
  rescue_from ArgumentError, ActiveRecord::RecordNotUnique, with: :invalid_request
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def capability
    render json: importer.capability(params[:inbox_id], params[:organization_id], params[:integration_id])
  end

  def create
    raise ArgumentError, 'request_bound' if request.raw_post.bytesize > 32_768 || request.query_parameters.present?

    render json: importer.call(params[:conversation_id], request.request_parameters)
  end

  def bootstrap
    raise ArgumentError, 'request_bound' if request.raw_post.bytesize > 32_768 || request.query_parameters.present?

    render json: importer.bootstrap(params[:inbox_id], request.request_parameters)
  end

  private

  def importer
    JrcBroker::HistoryImport.new(account: Current.account, user: @resource, access_token: @access_token)
  end

  def require_service_user
    response.headers['Cache-Control'] = 'no-store'
    raise Pundit::NotAuthorizedError unless authenticate_by_access_token? && @resource.is_a?(User)
  end

  def invalid_request
    render json: { error: 'JRC_HISTORY_IMPORT_INVALID' }, status: :conflict
  end

  def not_found
    render json: { error: 'JRC_HISTORY_IMPORT_SCOPE_NOT_FOUND' }, status: :not_found
  end
end
