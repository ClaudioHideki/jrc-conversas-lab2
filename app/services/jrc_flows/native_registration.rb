require 'securerandom'
require 'digest'

class JrcFlows::NativeRegistration
  def initialize(account_id:, user_id:)
    @account_id = account_id
    @user_id = user_id
    @authority = JrcFlows::NativeHostAuthority.new(account_id: account_id, user_id: user_id)
    @store = JrcFlows::NativeCredentialStore.for_application
  end

  def register!(challenge_id:, transfer_nonce:, inbox_ids:)
    valid = challenge_id.is_a?(String) && JrcFlows::NativeClient::UUID.match?(challenge_id) &&
            transfer_nonce.is_a?(String) && /\A[A-Za-z0-9_-]{43}\z/.match?(transfer_nonce) &&
            inbox_ids.is_a?(Array) && inbox_ids.length.between?(1, 100) && inbox_ids.uniq == inbox_ids && inbox_ids.all? do |id|
                                                                                                            id.is_a?(Integer) && id.positive?
                                                                                                          end
    fail!('FLOW_INVALID_REQUEST', 400) unless valid
    config, client, token = JrcFlows::NativeConfiguration.new(account_id: @account_id, user_id: @user_id).current!
    challenge = JrcFlows::NativeChallengeResponse.parse!(
      client.challenge(challenge_id, nonce: transfer_nonce), configuration: config, challenge_id: challenge_id, inbox_ids: inbox_ids
    )
    row = pending!(config, token, challenge, inbox_ids)
    unless challenge['state'] == 'COMMITTED'
      callback = @store.decrypt(account_id: @account_id, record_id: row.id, revision: row.revision,
                                purpose: 'PENDING_CALLBACK', ciphertext: row.encrypted_pending_callback)
      begin
        client.register(challenge_id: challenge_id, nonce: transfer_nonce, callback_credential: callback)
      rescue JrcFlows::NativeClient::Error
        # Read recovery is the same authorized operation; it never mints a second callback.
      end
      challenge = JrcFlows::NativeChallengeResponse.parse!(
        client.challenge(challenge_id, nonce: transfer_nonce), configuration: config, challenge_id: challenge_id, inbox_ids: inbox_ids
      )
    end
    fail!('FLOW_REGISTRATION_IN_PROGRESS', 409) unless challenge['state'] == 'COMMITTED'
    JrcFlowNativeRegistration.transaction do
      Account.lock('FOR SHARE').find(@account_id)
      row.lock!
      fail!('FLOW_REGISTRATION_CANCELED', 409) unless %w[CHALLENGE_VERIFIED ACTIVE].include?(row.state)
      fail!('FLOW_CONTEXT_CHANGED', 409) unless JrcFlowNativeConfiguration.current.exists?(id: config.id, revision: config.revision)
      @authority.administrator!
      @authority.authorize!(record: row, inbox_ids: inbox_ids, scopes: ['flow:bind'], nonce: SecureRandom.uuid)
      handle = challenge.fetch('registration')
      now = ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
      fail!('FLOW_REGISTRATION_EXPIRED', 409) unless Time.iso8601(handle['expiresAt']) > now
      if row.state == 'ACTIVE'
        fail!('FLOW_CONTEXT_CHANGED', 409) unless row.broker_registration_id == handle['id'] && row.broker_registration_revision == handle['revision']
      else
        row.update!(state: 'ACTIVE', broker_registration_id: handle['id'], broker_registration_revision: handle['revision'],
                    expires_at: handle['expiresAt'], encrypted_pending_callback: nil)
        row.tuple.fetch('targets').each do |target|
          row.bindings.create!(account_id: @account_id, inbox_id: target['inboxId'], integration_id: target['integrationId'],
                               channel_id: target['channelId'],
                               transport: target['transport'], provider: target['provider'], registration_revision: row.revision)
        end
      end
    end
    { id: row.id, state: row.state, expiresAt: row.expires_at.iso8601, inboxIds: inbox_ids }
  end

  def revoke!(id)
    JrcFlowNativeRegistration.transaction do
      Account.lock('FOR SHARE').find(@account_id)
      @authority.administrator!
      row = JrcFlowNativeRegistration.lock.find_by(account_id: @account_id, id: id)
      fail!('FLOW_REGISTRATION_NOT_FOUND', 404) unless row
      now = ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
      row.session_handles.update_all(encrypted_session_bearer: nil, closed_at: now, remote_close_pending: true)
      row.update!(state: row.state == 'ACTIVE' ? 'REVOKED' : 'CANCELED', revision: row.revision + 1, revoked_at: now,
                  callback_digest: nil, encrypted_outbound_credential: nil, encrypted_pending_callback: nil)
    end
    # Remote administrative revocation still uses the Broker OWNER/ADMIN route.
    { revoked: true, brokerAdministrativeRevocationRequired: true }
  end

  private

  def pending!(config, token, challenge, inbox_ids)
    JrcFlowNativeRegistration.transaction do
      Account.lock.find(@account_id)
      @authority.administrator!
      fail!('FLOW_CONTEXT_CHANGED', 409) unless JrcFlowNativeConfiguration.current.exists?(id: config.id, revision: config.revision)
      @authority.authorize!(record: config, inbox_ids: inbox_ids, scopes: ['flow:bind'], nonce: SecureRandom.uuid)
      row = JrcFlowNativeRegistration.find_by(account_id: @account_id, broker_origin: config.broker_origin, challenge_id: challenge['challengeId'])
      if row
        fail!('FLOW_REGISTRATION_CANCELED', 409) unless %w[PENDING CHALLENGE_VERIFIED ACTIVE].include?(row.state)
        unless row.created_by_id == @user_id && row.tuple == challenge['context'] && row.organization_id == config.organization_id
          fail!('FLOW_CONTEXT_CHANGED',
                409)
        end
        next row
      end
      fail!('FLOW_REGISTRATION_RECOVERY_REQUIRES_HOST_RECORD', 409) if challenge['state'] == 'COMMITTED'
      fail!('FLOW_REGISTRATION_REVOKE_REQUIRED', 409) if JrcFlowNativeRegistration.where(account_id: @account_id,
                                                                                         state: %w[
                                                                                           PENDING CHALLENGE_VERIFIED ACTIVE
                                                                                         ]).exists?
      now = ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
      fail!('FLOW_REGISTRATION_EXPIRED', 409) unless Time.iso8601(challenge['expiresAt']) > now
      row = JrcFlowNativeRegistration.create!(
        account_id: @account_id, created_by_id: @user_id, account_user_id: @authority.administrator!.id,
        broker_origin: config.broker_origin, host_origin: config.host_origin, organization_id: config.organization_id,
        challenge_id: challenge['challengeId'], credential_id: config.credential_id, credential_revision: config.credential_revision,
        destination_revision: config.destination_revision, account_credential_version: config.account_credential_version,
        tuple: challenge['context'], expires_at: challenge['expiresAt'], credential_expires_at: config.expires_at
      )
      callback = SecureRandom.urlsafe_base64(32)
      row.update!(callback_digest: Digest::SHA256.hexdigest(callback),
                  encrypted_pending_callback: @store.encrypt(account_id: @account_id, record_id: row.id, revision: row.revision,
                                                             purpose: 'PENDING_CALLBACK',
                                                             token: callback),
                  encrypted_outbound_credential: @store.encrypt(account_id: @account_id, record_id: row.id, revision: row.revision,
                                                                purpose: 'OUTBOUND',
                                                                token: token))
      row
    end
  end

  def fail!(code, status)
    raise JrcFlows::NativeClient::Error.new(code, status: status)
  end
end
