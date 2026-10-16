class JrcFlows::NativeEditor
  def initialize(account_id:, user_id:, handle_id:)
    @account_id = account_id
    @user_id = user_id
    @handle_id = handle_id
  end

  def call!(operation:, id: nil, cursor: nil, body: nil, idempotency_key: nil, target_id: nil, resource_id: nil)
    op = JrcFlows::NativeEditorOperation.resolve!(operation, id: id, cursor: cursor, target_id: target_id, resource_id: resource_id)
    handle, registration = authorize!(op.scope)
    token = JrcFlows::NativeCredentialStore.for_application.decrypt(
      account_id: @account_id, record_id: handle.id, revision: handle.credential_revision,
      purpose: 'SESSION_BEARER', ciphertext: handle.encrypted_session_bearer
    )
    result = JrcFlows::NativeClient.new(origin: registration.broker_origin, credential: token)
                                   .editor(op, body: body, idempotency_key: idempotency_key)
    current_handle, current_registration = authorize!(op.scope)
    fail!('FLOW_CONTEXT_CHANGED', 409) unless current_handle.id == handle.id && current_registration.id == registration.id &&
                                              current_registration.revision == registration.revision &&
                                              current_handle.encrypted_session_bearer == handle.encrypted_session_bearer
    result
  rescue JrcFlows::NativeEditorOperation::Invalid
    fail!('FLOW_INVALID_REQUEST', 400)
  end

  def context!
    handle, record = authorize!('flow:read')
    scopes = handle.scopes.select do |scope|
      JrcFlows::NativeHostAuthority.new(account_id: @account_id, user_id: @user_id)
                                   .authorize!(record: record, inbox_ids: handle.inbox_ids, scopes: [scope], nonce: handle.nonce)
      true
    rescue JrcFlows::NativeClient::Error, JrcFlows::NativeIntrospection::Denied
      false
    end
    { organizationId: record.organization_id, accountId: @account_id, actorId: @user_id, scopes: scopes, expiresAt: handle.expires_at.iso8601 }
  end

  def upload!(root_id:, channel_id:, io:, byte_size:, mime_type:, kind:, file_name:, idempotency_key:)
    handle, registration = authorize!('flow:edit')
    token = JrcFlows::NativeCredentialStore.for_application.decrypt(
      account_id: @account_id, record_id: handle.id, revision: handle.credential_revision,
      purpose: 'SESSION_BEARER', ciphertext: handle.encrypted_session_bearer
    )
    result = JrcFlows::NativeClient.new(origin: registration.broker_origin, credential: token).upload_media(
      root_id: root_id, channel_id: channel_id, io: io, byte_size: byte_size, mime_type: mime_type, kind: kind,
      file_name: file_name, idempotency_key: idempotency_key
    )
    fail!('FLOW_BROKER_INVALID_RESPONSE', 502) unless result.is_a?(Hash) && result['schemaVersion'] == 1 &&
                                                      result['scope'] == { 'organizationId' => registration.organization_id,
                                                                           'rootAutomationId' => root_id, 'channelId' => channel_id } &&
                                                      result.keys.sort == %w[byteSize id kind mimeType name revision schemaVersion scope
                                                                             status] && JrcFlows::NativeClient::UUID.match?(result['id'].to_s) &&
                                                      result['revision'].is_a?(Integer) && result['revision'].positive? &&
                                                      %w[READY STORING REVOKED].include?(result['status']) &&
                                                      result['kind'] == kind && result['mimeType'] == mime_type &&
                                                      result['byteSize'] == byte_size && result['name'].is_a?(String)
    current_handle, current_registration = authorize!('flow:edit')
    fail!('FLOW_CONTEXT_CHANGED', 409) unless current_handle.id == handle.id && current_registration.id == registration.id &&
                                              current_registration.revision == registration.revision &&
                                              current_handle.encrypted_session_bearer == handle.encrypted_session_bearer
    result
  end

  private

  def authorize!(scope)
    fail!('FLOW_SESSION_NOT_FOUND', 404) unless @handle_id.is_a?(String) && JrcFlows::NativeClient::UUID.match?(@handle_id)
    handle = JrcFlowNativeSessionHandle.find_by(account_id: @account_id, user_id: @user_id, public_id: @handle_id)
    fail!('FLOW_SESSION_NOT_FOUND', 404) unless handle
    now = ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
    if handle.closed_at || !handle.encrypted_session_bearer || handle.expires_at <= now || !handle.scopes.include?(scope)
      fail!('FLOW_SESSION_EXPIRED',
            403)
    end
    record = JrcFlowNativeRegistration.current.find_by(account_id: @account_id, id: handle.registration_id,
                                                       revision: handle.registration_revision, credential_revision: handle.credential_revision)
    fail!('FLOW_CONTEXT_CHANGED', 409) unless record && record.expires_at > now && record.credential_expires_at > now
    JrcFlows::NativeHostAuthority.new(account_id: @account_id, user_id: @user_id)
                                 .authorize!(record: record, inbox_ids: handle.inbox_ids, scopes: [scope], nonce: handle.nonce)
    [handle, record]
  end

  def fail!(code, status)
    raise JrcFlows::NativeClient::Error.new(code, status: status)
  end
end
