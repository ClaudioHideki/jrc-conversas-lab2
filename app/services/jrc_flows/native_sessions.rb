require 'securerandom'
require 'time'

class JrcFlows::NativeSessions
  def initialize(account_id:, user_id:, handles: nil, client_resolver: nil)
    @account_id = account_id
    @user_id = user_id
    @handles = handles || JrcFlowNativeSessionHandle
    @client_resolver = client_resolver || method(:client_for)
  end

  def issue!(inbox_ids:, scopes:)
    ids_valid = inbox_ids.is_a?(Array) && inbox_ids.length.between?(1, 100) && inbox_ids.uniq == inbox_ids && inbox_ids.all? do |id|
      id.is_a?(Integer) && id.positive?
    end
    scopes_valid = scopes.is_a?(Array) && scopes.any? && scopes.uniq == scopes && (scopes - JrcFlows::NativeIntrospection::SCOPES).empty?
    fail!('FLOW_INVALID_REQUEST', 400) unless ids_valid && scopes_valid
    registration = JrcFlowNativeRegistration.current.find_by(account_id: @account_id)
    fail!('FLOW_NATIVE_REGISTRATION_REQUIRED', 422) unless registration
    revision = registration.revision
    nonce = SecureRandom.uuid
    authority = JrcFlows::NativeHostAuthority.new(account_id: @account_id, user_id: @user_id)
    authority.authorize!(record: registration, inbox_ids: inbox_ids, scopes: scopes, nonce: nonce)
    bindings = registration.bindings.where(account_id: @account_id, inbox_id: inbox_ids, registration_revision: revision).to_a
    fail!('FLOW_CONTEXT_CHANGED', 409) unless bindings.map(&:inbox_id).sort == inbox_ids.sort
    result = @client_resolver.call(registration).issue_session(external_actor_id: @user_id.to_s, nonce: nonce,
                                                               integration_ids: bindings.map(&:integration_id), scopes: scopes)
    validate_response!(result)
    # Store a recovery handle before post-I/O authorization. A rejected issuance is
    # locally unusable and retains evidence if its remote reduction cannot finish.
    handle = @handles.create!(account_id: @account_id, registration_id: registration.id, user_id: @user_id,
                              public_id: SecureRandom.uuid, broker_session_id: result['id'], nonce: nonce,
                              credential_revision: registration.credential_revision, registration_revision: revision,
                              inbox_ids: inbox_ids, scopes: scopes, expires_at: result['expiresAt'], remote_close_pending: true)
    begin
      JrcFlowNativeRegistration.transaction do
        current = JrcFlowNativeRegistration.current.lock.find_by(id: registration.id, account_id: @account_id, revision: revision)
        fail!('FLOW_CONTEXT_CHANGED', 409) unless current
        authority.authorize!(record: current, inbox_ids: inbox_ids, scopes: scopes, nonce: nonce)
        now = ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
        fail!('FLOW_SESSION_EXPIRED', 409) unless Time.iso8601(result['expiresAt']) > now
        ciphertext = JrcFlows::NativeCredentialStore.for_application.encrypt(
          account_id: @account_id, record_id: handle.id, revision: handle.credential_revision, purpose: 'SESSION_BEARER', token: result['token']
        )
        handle.update!(encrypted_session_bearer: ciphertext, remote_close_pending: false)
      end
    rescue StandardError => e
      begin
        close!(handle.public_id)
      rescue StandardError
        # close! already removes local authority; the pending row is retained.
      end
      raise e
    end
    { id: handle.public_id, expiresAt: result['expiresAt'] }
  end

  def close!(public_id)
    fail!('FLOW_SESSION_NOT_FOUND', 404) unless public_id.is_a?(String) && JrcFlows::NativeClient::UUID.match?(public_id)
    handle = @handles.find_by(account_id: @account_id, user_id: @user_id, public_id: public_id)
    fail!('FLOW_SESSION_NOT_FOUND', 404) unless handle && handle.credential_revision == handle.registration.credential_revision
    return { revoked: true } if handle.closed_at && !handle.remote_close_pending

    handle.update!(closed_at: handle.closed_at || Time.current, encrypted_session_bearer: nil, remote_close_pending: true)
    result = @client_resolver.call(handle.registration).revoke_session(handle.broker_session_id, external_actor_id: @user_id.to_s,
                                                                                                 nonce: handle.nonce)
    fail!('FLOW_BROKER_INVALID_RESPONSE', 502) unless result == { 'revoked' => true }
    handle.update!(remote_close_pending: false)
    { revoked: true }
  end

  private

  def client_for(registration)
    token = JrcFlows::NativeCredentialStore.for_application.decrypt(
      account_id: @account_id, record_id: registration.id, revision: registration.revision,
      purpose: 'OUTBOUND', ciphertext: registration.encrypted_outbound_credential
    )
    JrcFlows::NativeClient.new(origin: registration.broker_origin, credential: token)
  end

  def validate_response!(result)
    valid = result.is_a?(Hash) && result.keys.sort == %w[expiresAt id token] && result['id'].is_a?(String) &&
            JrcFlows::NativeClient::UUID.match?(result['id']) && result['token'].is_a?(String) && /\A[A-Za-z0-9_-]{43}\z/.match?(result['token']) &&
            result['expiresAt'].is_a?(String) && result['expiresAt'].end_with?('Z')
    fail!('FLOW_BROKER_INVALID_RESPONSE', 502) unless valid
    Time.iso8601(result['expiresAt'])
  rescue ArgumentError
    fail!('FLOW_BROKER_INVALID_RESPONSE', 502)
  end

  def fail!(code, status)
    raise JrcFlows::NativeClient::Error.new(code, status: status)
  end
end
