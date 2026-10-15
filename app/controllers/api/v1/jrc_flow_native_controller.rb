class Api::V1::JrcFlowNativeController < ActionController::API
  wrap_parameters false
  before_action :boundary!
  rescue_from JrcFlows::NativeCallback::Denied, JrcFlows::NativeRegistrationProof::Denied, JrcFlows::NativeIntrospection::Denied, with: :denied
  rescue_from JrcFlows::NativeRateLimit::Limited, with: :rate_error
  rescue_from JrcFlows::NativeInstallationProof::Denied, with: :denied

  def introspect
    render json: JrcFlows::NativeCallback.new.call(authorization: request.headers['Authorization'], request: request.request_parameters)
  end

  def registration_challenge
    render json: JrcFlows::NativeRegistrationProof.new.call(bearer: bearer!, request: request.request_parameters)
  end

  def installation_challenge
    render json: JrcFlows::NativeInstallationProof.new.call(bearer: bearer!, request: request.request_parameters)
  end

  private

  def boundary!
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Pragma'] = 'no-cache'
    JrcFlows::NativeRateLimit.new.check!(ip: request.remote_ip, identity: request.headers['Authorization'].to_s, audience: 'callback')
    forbidden = %w[X-Organization-Id X-JRC-Organization-Id X-JRC-API-Key]
    raise JrcFlows::NativeCallback::Denied unless request.query_parameters.empty? && forbidden.none? { |header| request.headers[header].present? }

    bearer!
  end

  def bearer!
    match = /\ABearer ([A-Za-z0-9_-]{43})\z/.match(request.headers['Authorization'].to_s)
    raise JrcFlows::NativeCallback::Denied unless match

    match[1]
  end

  def denied(_error)
    render json: { code: 'FLOW_NATIVE_CALLBACK_DENIED' }, status: :forbidden
  end

  def rate_error(error)
    render json: { code: error.message }, status: error.status
  end
end
