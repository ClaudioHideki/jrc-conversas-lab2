require 'securerandom'
require 'digest'
class JrcFlows::NativeInstallations
  def initialize(account_id:, user_id:)
    @account_id = account_id
    @user_id = user_id
    @store = JrcFlows::NativeCredentialStore.for_application
    @authority = JrcFlows::NativeHostAuthority.new(account_id: account_id, user_id: user_id)
  end

  def claim!(grant_id:, transfer_nonce:)
    @authority.administrator!
    unless grant_id.is_a?(String) && JrcFlows::NativeClient::UUID.match?(grant_id) &&
           transfer_nonce.is_a?(String) && /\A[A-Za-z0-9_-]{43}\z/.match?(transfer_nonce)
      fail!('FLOW_INVALID_REQUEST',
            400)
    end
    row = JrcFlowNativeInstallation.transaction do
      Account.lock.find(@account_id)
      @authority.administrator!
      existing = JrcFlowNativeInstallation.find_by(account_id: @account_id, grant_id: grant_id)
      if existing
        fail!('FLOW_INSTALLATION_DENIED', 403) unless existing.created_by_id == @user_id && existing.state != 'REVOKED'
        fail!('FLOW_INSTALLATION_REPLAY_CHANGED', 409) unless open(existing, 'INSTALLATION_TRANSFER',
                                                                   existing.encrypted_transfer_nonce) == transfer_nonce
        existing
      else
        record = JrcFlowNativeRegistration.current.find_by!(account_id: @account_id)
        tuple = canonical_tuple(record)
        @authority.authorize!(record: record, inbox_ids: tuple['targets'].map { |t| t['inboxId'] }, scopes: ['flow:edit'], nonce: SecureRandom.uuid)
        callback = SecureRandom.urlsafe_base64(32, false)
        pending = JrcFlowNativeInstallation.create!(
          account_id: @account_id, created_by_id: @user_id, registration_id: record.id, grant_id: grant_id,
          tuple: tuple, tuple_digest: Digest::SHA256.hexdigest(JSON.generate(tuple)), operation_nonce: SecureRandom.uuid,
          callback_digest: Digest::SHA256.hexdigest(callback), encrypted_callback: '', operation_expires_at: sql_now + 5.minutes
        )
        pending.update!(encrypted_callback: seal(pending, 'INSTALLATION_CALLBACK', callback),
                        encrypted_transfer_nonce: seal(pending, 'INSTALLATION_TRANSFER', transfer_nonce))
        pending
      end
    end
    return metadata(row) if row.state == 'ACTIVE'

    lease!(row)
    begin
      record = row.registration.reload
      token = @store.decrypt(account_id: @account_id, record_id: record.id, revision: record.revision, purpose: 'OUTBOUND',
                             ciphertext: record.encrypted_outbound_credential)
      result = client(record, token).claim_installation(
        grant_id, { transferNonce: transfer_nonce, operationNonce: row.operation_nonce,
                    installationCallbackCredential: open(row, 'INSTALLATION_CALLBACK', row.encrypted_callback) }
      )
      valid = result.is_a?(Hash) && result.keys.sort == %w[credentialExpiresAt expiresAt generation id
                                                           token] && result['id'] == grant_id && result['generation'] == 1
      fail!('FLOW_BROKER_INVALID_RESPONSE', 502) unless valid
      expires = Time.iso8601(result.fetch('expiresAt'))
      Time.iso8601(result.fetch('credentialExpiresAt'))
      JrcFlowNativeInstallation.transaction do
        current = row.reload.lock!
        @authority.administrator!
        @authority.authorize!(record: record.reload, inbox_ids: row.tuple.fetch('targets').map do |t|
          t['inboxId']
        end, scopes: ['flow:edit'], nonce: row.operation_nonce)
        unless current.state == 'PENDING' && current.lease_until && current.lease_until > sql_now &&
               expires > sql_now && expires <= current.created_at + 30.days
          fail!('FLOW_CONTEXT_CHANGED',
                409)
        end
        current.update!(state: 'ACTIVE', encrypted_grant: seal(current, 'INSTALLATION_GRANT', result.fetch('token')), expires_at: expires,
                        lease_until: nil)
      end
      metadata(row.reload)
    rescue StandardError
      row.update!(lease_until: nil) unless row.reload.state == 'REVOKED'
      raise
    end
  end

  def renew!(id)
    row = JrcFlowNativeInstallation.find_by!(id: id, account_id: @account_id, created_by_id: @user_id)
    @authority.administrator!
    return metadata(row) unless %w[ACTIVE RENEWING UNKNOWN].include?(row.state)

    record = row.registration.reload
    return metadata(row) if row.state == 'ACTIVE' && record.credential_expires_at > sql_now + 6.hours

    JrcFlowNativeInstallation.transaction do
      row.lock!
      fail!('FLOW_INSTALLATION_EXPIRED', 403) unless row.expires_at && row.expires_at > sql_now
      if row.state == 'ACTIVE'
        pending_callback = SecureRandom.urlsafe_base64(32, false)
        row.update!(state: 'RENEWING', operation_nonce: SecureRandom.uuid, proof_nonce: nil,
                    encrypted_renew_callback: seal(row, 'RENEW_CALLBACK', pending_callback), operation_expires_at: sql_now + 5.minutes)
      end
    end
    lease!(row)
    begin
      result = client(record, open(row, 'INSTALLATION_GRANT', row.encrypted_grant)).renew_installation(
        row.grant_id, { operationNonce: row.operation_nonce, expectedGeneration: row.generation,
                        expectedCredentialId: record.credential_id, expectedCredentialRevision: record.credential_revision,
                        nativeCallbackCredential: open(row, 'RENEW_CALLBACK', row.encrypted_renew_callback) }
      )
      valid = result.is_a?(Hash) && result.keys.sort == %w[credential expiresAt generation id
                                                           registration] && result['id'] == row.grant_id && result['generation'] == row.generation + 1
      fail!('FLOW_BROKER_INVALID_RESPONSE', 502) unless valid
      c, r = result.values_at('credential', 'registration')
      fail!('FLOW_BROKER_INVALID_RESPONSE', 502) unless c.is_a?(Hash) && c.keys.sort == %w[expiresAt id revision
                                                                                           token] && r.is_a?(Hash) && r.keys.sort == %w[expiresAt id
                                                                                                                                        revision] &&
                                                        JrcFlows::NativeClient::UUID.match?(c['id'].to_s) &&
                                                        JrcFlows::NativeClient::UUID.match?(r['id'].to_s) &&
                                                        c['revision'].is_a?(Integer) && c['revision'].positive? &&
                                                        r['revision'].is_a?(Integer) && r['revision'].positive? && c['expiresAt'] == r['expiresAt']
      expiry = Time.iso8601(c['expiresAt'])
      JrcFlowNativeInstallation.transaction do
        Account.lock.find(@account_id)
        row.lock!
        @authority.administrator!
        @authority.authorize!(record: record.reload, inbox_ids: row.tuple.fetch('targets').map do |t|
          t['inboxId']
        end, scopes: ['flow:edit'], nonce: row.operation_nonce)
        fail!('FLOW_CONTEXT_CHANGED', 409) unless %w[RENEWING UNKNOWN].include?(row.state) && row.lease_until &&
                                                row.lease_until > sql_now && expiry > sql_now && expiry <= row.expires_at &&
                                                expiry <= sql_now + 24.hours && Time.iso8601(result['expiresAt']) == row.expires_at
        callback = open(row, 'RENEW_CALLBACK', row.encrypted_renew_callback)
        record.session_handles.update_all(closed_at: sql_now, encrypted_session_bearer: nil, remote_close_pending: true)
        record.update!(state: 'REVOKED', revoked_at: sql_now, encrypted_outbound_credential: nil, encrypted_pending_callback: nil,
                       callback_digest: nil)
        fresh = JrcFlowNativeRegistration.create!(
          record.attributes.except(
            'id', 'created_at', 'updated_at', 'broker_registration_id', 'broker_registration_revision', 'credential_id',
            'credential_revision', 'callback_digest', 'revoked_at', 'state', 'encrypted_outbound_credential'
          ).merge(
            state: 'PENDING', challenge_id: SecureRandom.uuid, revision: record.revision + 1,
            credential_id: c['id'], credential_revision: c['revision'], broker_registration_id: r['id'],
            broker_registration_revision: r['revision'], expires_at: expiry, credential_expires_at: expiry
          )
        )
        fresh.update!(state: 'ACTIVE', callback_digest: Digest::SHA256.hexdigest(callback),
                      encrypted_outbound_credential: @store.encrypt(account_id: @account_id, record_id: fresh.id,
                                                                    revision: fresh.revision, purpose: 'OUTBOUND', token: c['token']))
        row.tuple.fetch('targets').each do |t|
          fresh.bindings.create!(account_id: @account_id, inbox_id: t['inboxId'], integration_id: t['integrationId'], channel_id: t['channelId'],
                                 transport: t['transport'], provider: t['provider'], registration_revision: fresh.revision)
        end
        row.update!(state: 'ACTIVE', registration_id: fresh.id, generation: result['generation'], encrypted_renew_callback: nil, lease_until: nil)
        configuration = JrcFlowNativeConfiguration.lock.find_by(account_id: @account_id)
        if configuration
          revision = configuration.revision + 1
          configuration.update!(credential_id: c['id'], credential_revision: c['revision'], expires_at: expiry, revision: revision,
                                encrypted_outbound_credential: @store.encrypt(account_id: @account_id, record_id: @account_id,
                                                                              revision: revision, purpose: 'CONFIGURATION_OUTBOUND',
                                                                              token: c['token']))
        end
      end
      metadata(row.reload)
    rescue StandardError
      row.update!(state: 'UNKNOWN', lease_until: nil) unless row.reload.state == 'REVOKED'
      raise
    end
  end

  def revoke!(grant_id)
    # Reduce only: the persisted installer identity is enough after membership loss.
    row = JrcFlowNativeInstallation.find_by!(account_id: @account_id, grant_id: grant_id, created_by_id: @user_id)
    return { revoked: true } if row.state == 'REVOKED' && !row.remote_revoke_pending

    JrcFlowNativeInstallation.transaction do
      row.lock!
      if row.state != 'REVOKED'
        token = open(row, 'INSTALLATION_GRANT', row.encrypted_grant)
        record = row.registration.lock!
        record.session_handles.update_all(closed_at: sql_now, encrypted_session_bearer: nil, remote_close_pending: true)
        record.update!(state: 'REVOKED', revoked_at: sql_now, encrypted_outbound_credential: nil, encrypted_pending_callback: nil,
                       callback_digest: nil)
        row.update!(state: 'REVOKED', revoked_at: sql_now, encrypted_grant: nil, encrypted_callback: '', encrypted_renew_callback: nil,
                    encrypted_transfer_nonce: nil, encrypted_revoke_bearer: seal(row, 'INSTALLATION_REVOKE', token),
                    operation_nonce: SecureRandom.uuid, remote_revoke_pending: true, lease_until: nil)
      end
    end
    result = client(row.registration, open(row, 'INSTALLATION_REVOKE', row.encrypted_revoke_bearer)).revoke_installation(
      grant_id, { expectedGeneration: row.generation, operationNonce: row.operation_nonce }
    )
    fail!('FLOW_BROKER_INVALID_RESPONSE', 502) unless result == { 'revoked' => true }
    row.update!(encrypted_revoke_bearer: nil, remote_revoke_pending: false)
    { revoked: true }
  end

  private

  def canonical_tuple(record)
    {
      'accountId' => record.account_id, 'destinationRevision' => record.destination_revision,
      'accountCredentialVersion' => record.account_credential_version,
      'targets' => record.tuple.fetch('targets').sort_by do |t|
        t.fetch('integrationId')
      end.map do |t|
        { 'integrationId' => t.fetch('integrationId'), 'channelId' => t.fetch('channelId'), 'inboxId' => t.fetch('inboxId'),
          'transport' => t.fetch('transport'), 'provider' => t['provider'] }
      end
    }
  end

  def lease!(row)
    changed = JrcFlowNativeInstallation.where(
      id: row.id, account_id: @account_id, created_by_id: @user_id, state: %w[PENDING RENEWING UNKNOWN]
    ).where(
      'operation_expires_at>clock_timestamp() AND (lease_until IS NULL OR lease_until<=clock_timestamp())'
    ).update_all("lease_until=clock_timestamp()+interval '15 seconds'")
    fail!('FLOW_INSTALLATION_IN_PROGRESS', 409) unless changed == 1
    row.reload
  end

  def seal(row, purpose, token) = @store.encrypt(account_id: @account_id, record_id: row.id, revision: 1, purpose: purpose, token: token)
  def open(row, purpose, cipher) = @store.decrypt(account_id: @account_id, record_id: row.id, revision: 1, purpose: purpose, ciphertext: cipher)
  def client(record, token) = JrcFlows::NativeClient.new(origin: record.broker_origin, credential: token)
  def sql_now = ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
  def metadata(row) = { id: row.grant_id, generation: row.generation, state: row.state, expiresAt: row.expires_at&.iso8601 }
  def fail!(code, status) = raise(JrcFlows::NativeClient::Error.new(code, status: status))
end
