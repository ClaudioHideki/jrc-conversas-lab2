class JrcBroker::Context
  attr_reader :account, :user, :integration, :client

  def initialize(account:, user: nil, actor_id: nil, release_connection: false)
    @account = account
    @user = user
    @integration = JrcBrokerIntegration.find_by!(account_id: account.id)
    @configuration_snapshot = integration.attributes.slice('broker_origin', 'organization_id', 'destination_revision', 'encrypted_control_key').freeze
    token = JrcBroker::Configuration.credential_store.decrypt(account_id: account.id, ciphertext: integration.encrypted_control_key)
    @client = JrcBroker::Client.new(origin: integration.broker_origin, token: token, actor_id: resolve_actor_id(actor_id),
                                  release_connection: release_connection)
    release_idle_connection if release_connection
    validate_remote_context!
  end

  def binding(inbox_id)
    inbox = account.inboxes.find(inbox_id)
    JrcBrokerInboxBinding.find_by!(account_id: account.id, inbox_id: inbox.id)
  end

  def bind_completed!(operation)
    return operation unless operation['state'] == 'SUCCEEDED'

    inbox = account.inboxes.find(operation.fetch('inboxId'))
    raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE' unless inbox.channel_type == 'Channel::Api'

    # Network verification precedes the local transaction and never creates an inbox.
    status = client.status(operation.fetch('integrationId'))
    unless status['integrationStatus'] == 'READY' &&
           status.values_at('integrationId', 'inboxId', 'instanceId') == operation.values_at('integrationId', 'inboxId', 'instanceId')
      raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE'
    end

    save_binding!(inbox, operation)
    operation
  end

  def adopt!(integration_id)
    status = client.status(integration_id)
    unless status['integrationId'] == integration_id && status['integrationStatus'] == 'READY' &&
           JrcBroker::Client::UUID.match?(status['instanceId'].to_s)
      raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE'
    end

    inbox = account.inboxes.find(status.fetch('inboxId'))
    raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE' unless inbox.channel_type == 'Channel::Api'

    save_binding!(inbox, status)
    { inboxId: inbox.id, integrationId: integration_id }
  end

  # Discovery is authenticated by the account-scoped control credential. A callback
  # URL alone is never sufficient, and registration never confirms a phone number.
  def sync_inboxes!(after_inbox_id: 0)
    pending = unbound_discoveries(after_inbox_id)
    registered = pending.first(10).count { |row| sync_inbox!(row) }
    { registered: registered, next_after: pending.size > 10 ? pending[9].fetch('inboxId') : nil }
  end

  private

  def release_idle_connection
    pool = ActiveRecord::Base.connection_pool
    connection = pool.active_connection?
    pool.release_connection if connection && !connection.transaction_open?
  end

  def validate_remote_context!
    remote = client.context
    JrcBroker::Configuration.validate_context!(remote, account.id, @configuration_snapshot.fetch('organization_id'))
    return if remote['destinationRevision'] == @configuration_snapshot.fetch('destination_revision')

    raise JrcBroker::Client::Error.new('JRC_BROKER_CONTEXT_CHANGED', status: 409)
  end

  def unbound_discoveries(after_inbox_id)
    connections = client.resources['connections']
    validate_discovery!(connections)
    candidates = account.inboxes.where(channel_type: 'Channel::Api', id: connections.pluck('inboxId')).includes(:channel).index_by(&:id)
    bound_ids = JrcBrokerInboxBinding.where(account_id: account.id).pluck(:inbox_id)
    pending = connections.select do |row|
      eligible_discovery?(row, candidates[row['inboxId']], bound_ids, after_inbox_id)
    end
    pending.sort_by { |row| row['inboxId'] }
  end

  def eligible_discovery?(row, inbox, bound_ids, after_inbox_id)
    row['inboxId'] > after_inbox_id && bound_ids.exclude?(row['inboxId']) &&
      inbox && inbox.channel.webhook_url == callback(row['integrationId'])
  end

  def callback(integration_id)
    "#{@configuration_snapshot.fetch('broker_origin')}/v1/integrations/chatwoot/#{integration_id}/events"
  end

  def validate_discovery!(connections)
    valid = connections.is_a?(Array) && connections.size <= 500 && connections.all? { |row| valid_discovery_row?(row) }
    valid &&= connections.pluck('integrationId').uniq.size == connections.size && connections.pluck('inboxId').uniq.size == connections.size
    raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE' unless valid
  end

  def valid_discovery_row?(row)
    row.is_a?(Hash) && JrcBroker::Client::UUID.match?(row['integrationId'].to_s) && row['inboxId'].is_a?(Integer) && row['inboxId'].positive?
  end

  def sync_inbox!(row)
    inbox = account.inboxes.find(row.fetch('inboxId'))
    integration_id = row.fetch('integrationId')
    status = client.status(integration_id)
    return false unless status.values_at('integrationId', 'inboxId', 'integrationStatus') == [integration_id, inbox.id, 'READY'] &&
                        JrcBroker::Client::UUID.match?(status['instanceId'].to_s)

    save_binding!(inbox, status, automatic: true)
    true
  rescue JrcBroker::Client::Error, ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # A conflicting/unready inbox cannot prevent discovery of the other senders.
    false
  end

  def resolve_actor_id(actor_id)
    value = actor_id || user&.id
    raise ArgumentError, 'Ator interno inválido.' unless value.is_a?(Integer) && value.positive?

    value
  end

  def save_binding!(inbox, operation, automatic: false)
    return save_binding_under_locks!(inbox, operation) unless automatic

    # Configuration changes lock Account before integration. Keep the same order
    # here and finish every HTTP call before entering this transaction.
    account.with_lock do
      authorize_automatic_registration!
      save_binding_under_locks!(inbox, operation, automatic: true)
    end
  end

  def authorize_automatic_registration!
    member = account.account_users.lock.find_by(user_id: user&.id)
    actor_context = { account: account, user: user, account_user: member }
    return if JrcBrokerPolicy.new(actor_context, nil).manage?

    raise JrcBroker::Client::Error.new('JRC_BROKER_FORBIDDEN', status: 403)
  end

  def save_binding_under_locks!(inbox, operation, automatic: false)
    integration.with_lock do
      unless @configuration_snapshot == integration.attributes.slice(*@configuration_snapshot.keys)
        raise JrcBroker::Client::Error.new('JRC_BROKER_CONTEXT_CHANGED', status: 409)
      end

      inbox.with_lock do
        validate_automatic_callback!(inbox, operation) if automatic
        assign_binding!(inbox, operation)
      end
    end
  end

  def validate_automatic_callback!(inbox, operation)
    inbox.channel.lock!
    return if JrcBroker::Configuration.enabled? && account.reload.feature_enabled?('jrc_broker') &&
              inbox.channel.webhook_url == callback(operation.fetch('integrationId'))

    raise JrcBroker::Client::Error.new('JRC_BROKER_CALLBACK_MISMATCH', status: 409)
  end

  def assign_binding!(inbox, operation)
    binding = JrcBrokerInboxBinding.find_or_initialize_by(account_id: account.id, inbox_id: inbox.id)
    if binding.persisted? && binding.integration_id != operation['integrationId']
      raise JrcBroker::Client::Error.new('JRC_BROKER_ALREADY_BOUND', status: 409)
    end

    binding.update!(integration_id: operation.fetch('integrationId'), instance_id: operation.fetch('instanceId'))
  end
end
