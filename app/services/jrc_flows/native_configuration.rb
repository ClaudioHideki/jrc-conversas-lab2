class JrcFlows::NativeConfiguration
  def initialize(account_id:, user_id:, store: nil, client_factory: nil)
    @account_id = account_id
    @user_id = user_id
    @authority = JrcFlows::NativeHostAuthority.new(account_id: account_id, user_id: user_id)
    @store = store || JrcFlows::NativeCredentialStore.for_application
    @client_factory = client_factory || ->(origin, token) { JrcFlows::NativeClient.new(origin: origin, credential: token) }
  end

  def configure!(origin:, token:)
    @authority.administrator!
    host_origin = ENV.fetch('FRONTEND_URL').delete_suffix('/')
    context = JrcFlows::NativeContextResponse.parse!(@client_factory.call(origin, token).context, account_id: @account_id, origin: host_origin)
    c, d = context.values_at('credential', 'destination')
    JrcFlowNativeConfiguration.transaction do
      # Serializes initial creation as well as updates without holding a lock across HTTP.
      Account.lock.find(@account_id)
      @authority.administrator!
      if JrcFlowNativeRegistration.where(account_id: @account_id, state: %w[PENDING CHALLENGE_VERIFIED ACTIVE]).exists?
        raise JrcFlows::NativeClient::Error.new('FLOW_REGISTRATION_REVOKE_REQUIRED', status: 409)
      end

      now = ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
      raise JrcFlows::NativeClient::Error.new('FLOW_NATIVE_CREDENTIAL_EXPIRED', status: 409) unless Time.iso8601(c['expiresAt']) > now

      row = JrcFlowNativeConfiguration.find_or_initialize_by(account_id: @account_id)
      revision = row.persisted? ? row.revision + 1 : 1
      row.assign_attributes(created_by_id: @user_id, broker_origin: origin, host_origin: host_origin, organization_id: d['organizationId'],
                            credential_id: c['id'], credential_revision: c['revision'], destination_revision: d['destinationRevision'],
                            account_credential_version: d['accountCredentialVersion'], expires_at: c['expiresAt'], revision: revision,
                            encrypted_outbound_credential: @store.encrypt(account_id: @account_id, record_id: @account_id, revision: revision,
                                                                          purpose: 'CONFIGURATION_OUTBOUND', token: token))
      row.save!
    end
    metadata
  end

  def metadata
    @authority.administrator!
    row = JrcFlowNativeConfiguration.find_by(account_id: @account_id)
    { configured: row.present?, brokerOrigin: row&.broker_origin, credentialExpiresAt: row&.expires_at&.iso8601,
      revision: row&.revision, allowedOrigins: ENV.fetch('JRC_BROKER_ALLOWED_ORIGINS', '').split(',').map(&:strip) }
  end

  def current!
    @authority.administrator!
    row = JrcFlowNativeConfiguration.current.find_by(account_id: @account_id)
    raise JrcFlows::NativeClient::Error.new('FLOW_NATIVE_CONFIGURATION_REQUIRED', status: 422) unless row

    token = @store.decrypt(account_id: @account_id, record_id: @account_id, revision: row.revision,
                           purpose: 'CONFIGURATION_OUTBOUND', ciphertext: row.encrypted_outbound_credential)
    [row, @client_factory.call(row.broker_origin, token), token]
  end
end
