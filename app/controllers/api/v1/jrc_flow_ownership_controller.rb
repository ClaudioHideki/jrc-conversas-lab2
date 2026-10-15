class Api::V1::JrcFlowOwnershipController < ActionController::API
  wrap_parameters false
  before_action :boundary!
  rescue_from JrcFlows::NativeOwnership::Denied, JrcFlows::NativeCallback::Denied, JrcFlows::NativeIntrospection::Denied, with: :denied
  rescue_from JrcFlows::NativeOwnership::NotDrained, with: :not_drained
  rescue_from JrcFlows::NativeRateLimit::Limited, with: :limited
  def fence = render(json: JrcFlows::NativeOwnership.new.fence!(registration: @registration, request: request.request_parameters))
  def observe = render(json: JrcFlows::NativeOwnership.new.observe!(registration: @registration, request: request.request_parameters))
  def retire = render(json: JrcFlows::NativeOwnership.new.retire!(registration: @registration, request: request.request_parameters))
  def rollback = render(json: JrcFlows::NativeOwnership.new.reopen!(registration: @registration, request: request.request_parameters))

  private

  def boundary!
    response.headers['Cache-Control']='no-store'
    response.headers['Pragma']='no-cache'
    JrcFlows::NativeRateLimit.new.check!(ip: request.remote_ip, identity: request.headers['Authorization'].to_s, audience: 'callback')
    raise JrcFlows::NativeCallback::Denied unless request.query_parameters.empty? && %w[X-Organization-Id X-JRC-Organization-Id
                                                                                        X-JRC-API-Key].none? do |h|
      request.headers[h].present?
    end

    match=/\ABearer ([A-Za-z0-9_-]{43})\z/.match(request.headers['Authorization'].to_s)
    raise JrcFlows::NativeCallback::Denied unless match

    input=request.request_parameters
    decision=JrcFlows::NativeCallback.new.call(authorization: request.headers['Authorization'],
                                               request: { 'nonce' => input['nonce'], 'externalActorId'=>input['externalActorId'],
                                                          'accountId'=>input['accountId'],
                                                          'destinationRevision' => input['destinationRevision'], 'inboxIds'=>[input['inboxId']] })
    decision=decision.with_indifferent_access
    unless decision['member'] && decision['accountActive'] && decision['featureEnabled'] && decision['role']=='administrator'
      raise JrcFlows::NativeCallback::Denied
    end

    @registration=JrcFlowNativeRegistration.current.find_by(callback_digest: Digest::SHA256.hexdigest(match[1]))
    raise JrcFlows::NativeCallback::Denied unless @registration
  end

  def denied(_error) = render(json: { code: 'FLOW_OWNERSHIP_AUTHORITY_CHANGED' }, status: :forbidden)
  def not_drained(_error) = render(json: { code: 'FLOW_OWNERSHIP_NOT_DRAINED' }, status: :conflict)
  def limited(error) = render(json: { code: error.message }, status: error.status)
end
