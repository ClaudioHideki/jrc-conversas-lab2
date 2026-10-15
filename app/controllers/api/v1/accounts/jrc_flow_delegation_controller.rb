class Api::V1::Accounts::JrcFlowDelegationController < Api::V1::Accounts::BaseController
  wrap_parameters false
  before_action :boundary!
  rescue_from JrcFlows::NativeClient::Error, JrcFlows::NativeRateLimit::Limited, with: :service_error
  rescue_from JrcFlows::NativeIntrospection::Denied, with: :authority_error
  rescue_from JrcFlows::NativeContextResponse::Invalid, JrcFlows::NativeCredentialStore::Unavailable, with: :context_error

  def configuration
    render json: native_configuration.metadata
  end

  def configure
    input = body!('brokerOrigin', 'nativeCredential')
    render json: native_configuration.configure!(origin: input['brokerOrigin'], token: input['nativeCredential'])
  end

  def register
    input = body!('challengeId', 'transferNonce', 'inboxIds')
    render json: registration.register!(challenge_id: input['challengeId'], transfer_nonce: input['transferNonce'], inbox_ids: input['inboxIds'])
  end

  def revoke_registration
    body!
    render json: registration.revoke!(params[:id])
  end

  def create_session
    input = body!('inboxIds', 'scopes')
    render json: sessions.issue!(inbox_ids: input['inboxIds'], scopes: input['scopes']), status: :created
  end

  def close_session
    body!
    render json: sessions.close!(params[:id])
  end

  def editor
    render json: JrcFlows::NativeEditor.new(**identity, handle_id: params[:session_id]).call!(
      operation: params[:editor_operation], id: params[:id], cursor: request.query_parameters['cursor'],
      target_id: params[:target_id], resource_id: params[:resource_id],
      body: request.get? ? nil : request.request_parameters,
      idempotency_key: params[:editor_operation] == 'create' ? request.headers['Idempotency-Key'] : nil
    )
  end

  def editor_context
    render json: JrcFlows::NativeEditor.new(**identity, handle_id: params[:session_id]).context!
  end

  def upload_media
    raise JrcFlows::NativeClient::Error.new('FLOW_INVALID_REQUEST', status: 400) unless request.content_type == 'application/octet-stream'

    render json: JrcFlows::NativeEditor.new(**identity, handle_id: params[:session_id]).upload!(
      root_id: params[:id], channel_id: params[:channel_id], io: request.body, byte_size: request.content_length,
      mime_type: request.headers['X-JRC-Media-Mime'], kind: request.headers['X-JRC-Media-Kind'],
      file_name: request.headers['X-JRC-Media-Name'], idempotency_key: request.headers['Idempotency-Key']
    )
  end

  def claim_installation
    input = body!('grantId', 'transferNonce')
    render json: JrcFlows::NativeInstallations.new(**identity).claim!(grant_id: input['grantId'], transfer_nonce: input['transferNonce'])
  end

  def revoke_installation
    body!
    render json: JrcFlows::NativeInstallations.new(**identity).revoke!(params[:id])
  end

  private

  def identity
    { account_id: Current.account.id, user_id: Current.user.id }
  end

  def native_configuration
    JrcFlows::NativeConfiguration.new(**identity)
  end

  def registration
    JrcFlows::NativeRegistration.new(**identity)
  end

  def sessions
    JrcFlows::NativeSessions.new(**identity)
  end

  def boundary!
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Pragma'] = 'no-cache'
    paginated = params[:action] == 'editor' && JrcFlows::NativeEditorOperation::PAGINATED.include?(params[:editor_operation])
    allowed_query = paginated ? %w[cursor] : []
    raise JrcFlows::NativeClient::Error.new('FLOW_INVALID_REQUEST', status: 400) unless (request.query_parameters.keys - allowed_query).empty?

    if request.headers['X-Organization-Id'] || request.headers['X-JRC-Organization-Id'] || request.headers['X-JRC-API-Key']
      raise JrcFlows::NativeClient::Error.new('FLOW_INVALID_REQUEST',
                                              status: 400)
    end

    JrcFlows::NativeRateLimit.new.check!(ip: request.remote_ip, identity: "#{Current.account.id}:#{Current.user.id}", audience: 'browser')
    return if request.get? || request.head? || authenticate_by_access_token? || verified_header_token? || verified_request?

    raise JrcFlows::NativeClient::Error.new('FLOW_CSRF_REQUIRED', status: 403)
  end

  def verified_header_token?
    token = request.headers['access-token']
    token.present? && Current.user.valid_token?(token, request.headers['client'].presence || 'default')
  end

  def body!(*keys)
    value = request.request_parameters
    raise JrcFlows::NativeClient::Error.new('FLOW_INVALID_REQUEST', status: 400) unless value.is_a?(Hash) && value.keys.sort == keys.sort

    value
  end

  def service_error(error)
    render json: { code: error.message }, status: error.status
  end

  def authority_error(error)
    render json: { code: error.message }, status: :forbidden
  end

  def context_error(_error)
    render json: { code: 'FLOW_NATIVE_CONFIGURATION_INVALID' }, status: :unprocessable_entity
  end

  def render_unauthorized(_message)
    render json: { code: 'FLOW_ACCESS_DENIED' }, status: :forbidden
  end
end
