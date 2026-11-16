class Api::V1::Accounts::JrcBrokerLiveIngressController < Api::V1::Accounts::BaseController
  wrap_parameters false
  before_action :require_service_user
  rescue_from ArgumentError, ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid, with: :conflict
  rescue_from JrcBroker::LiveIngress::NotFound, with: :missing_receipt
  rescue_from JrcBroker::LiveIngress::Backpressure, with: :backpressure
  rescue_from JrcBroker::LiveIngress::Forbidden, with: :forbidden

  def capability
    render json: receiver.capability(params[:inbox_id], bounded_body)
  end

  def create
    if request.media_type == 'multipart/form-data'
      input = multipart_parameters
      render json: receiver.receive(params[:inbox_id], JSON.parse(input.fetch('envelope')), input.fetch('file'))
    else
      render json: receiver.receive(params[:inbox_id], bounded_body)
    end
  rescue JSON::ParserError, TypeError
    conflict
  end

  def receipt
    render json: receiver.lookup(params[:inbox_id], params[:broker_message_id], bounded_body)
  end

  private

  def multipart_parameters
    input = request.request_parameters
    valid = request.query_parameters.empty? && input.keys.sort == %w[envelope file] && input['envelope'].is_a?(String) &&
            input['envelope'].bytesize <= JrcBroker::LiveIngressBodyLimit::JSON_LIMIT
    raise ArgumentError, 'JRC_LIVE_INPUT' unless valid

    input
  end

  def bounded_body
    raise ArgumentError, 'JRC_LIVE_INPUT' unless request.media_type == 'application/json' &&
                                                 request.raw_post.bytesize <= JrcBroker::LiveIngressBodyLimit::JSON_LIMIT &&
                                                 request.query_parameters.empty?

    request.request_parameters
  end

  def require_service_user
    response.headers['Cache-Control'] = 'no-store'
    forbidden unless authenticate_by_access_token? && @resource.is_a?(User)
  end

  def receiver
    JrcBroker::LiveIngress.new(account: Current.account, user: @resource, access_token: @access_token)
  end

  def conflict
    render json: { error: 'JRC_LIVE_CONFLICT' }, status: :conflict
  end

  def missing_receipt
    render json: { error: 'JRC_LIVE_RECEIPT_NOT_FOUND' }, status: :not_found
  end

  def backpressure
    render json: { error: 'JRC_LIVE_MEDIA_BACKPRESSURE' }, status: :too_many_requests
  end

  def forbidden
    render json: { error: 'JRC_LIVE_FORBIDDEN' }, status: :forbidden
  end

  def render_not_found_error(_message)
    conflict
  end
end
