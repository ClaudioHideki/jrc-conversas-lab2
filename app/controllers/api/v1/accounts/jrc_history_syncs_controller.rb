class Api::V1::Accounts::JrcHistorySyncsController < Api::V1::Accounts::BaseController
  wrap_parameters false
  before_action :require_service_user
  rescue_from ArgumentError, ActiveRecord::RecordNotUnique, with: :invalid_request
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def capability
    render json: importer.capability(params[:inbox_id], request.query_parameters)
  end

  def bootstrap
    render json: importer.bootstrap(params[:inbox_id], bounded_body)
  end

  def create
    render json: importer.call(params[:inbox_id], bounded_body)
  end

  def media
    input = media_parameters
    scope = JSON.parse(input.fetch('scope'))
    metadata = JSON.parse(input.fetch('metadata'))
    render json: JrcBroker::HistorySyncMedia.new(importer).upload(params[:inbox_id], scope, metadata, input.fetch('file'))
  rescue JSON::ParserError, TypeError
    invalid_request
  end

  def receipt
    render json: importer.receipt(params[:inbox_id], params[:receipt_id], request.query_parameters)
  end

  private

  def media_parameters
    input = request.request_parameters
    raise ArgumentError, 'historical_media_request' unless request.query_parameters.empty? && input.keys.sort == %w[file metadata scope]
    raise ArgumentError, 'historical_media_metadata_bound' unless %w[scope metadata].all? do |key|
      input[key].is_a?(String) && input[key].bytesize <= 16_384
    end

    input
  end

  def bounded_body
    raise ArgumentError, 'request_bound' if request.raw_post.bytesize > 32_768 || request.query_parameters.present?

    request.request_parameters
  end

  def importer
    JrcBroker::HistorySyncV2.new(account: Current.account, user: @resource, access_token: @access_token)
  end

  def require_service_user
    response.headers['Cache-Control'] = 'no-store'
    raise Pundit::NotAuthorizedError unless authenticate_by_access_token? && @resource.is_a?(User)
  end

  def invalid_request
    render json: { error: 'JRC_HISTORY_SYNC_INVALID' }, status: :conflict
  end

  def not_found
    render json: { error: 'JRC_HISTORY_SYNC_SCOPE_NOT_FOUND' }, status: :not_found
  end
end
