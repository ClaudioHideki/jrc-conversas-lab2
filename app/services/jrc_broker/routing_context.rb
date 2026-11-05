require 'time'

class JrcBroker::RoutingContext
  TUPLE_FIELDS = %w[id account_id inbox_id integration_id instance_id channel_id registration_id registration_revision].freeze

  def initialize(account:, user:, bindings:)
    @account = account
    @user = user
    @bindings = bindings
  end

  def perform
    return {} unless JrcBroker::Configuration.enabled?

    integration = JrcBrokerIntegration.find_by(account_id: @account.id)
    return {} unless integration

    snapshot = integration.attributes.slice('broker_origin', 'organization_id', 'destination_revision', 'encrypted_control_key')
    tuples = @bindings.map { |binding| [binding.class, binding.attributes.slice(*TUPLE_FIELDS)] }
    return {} unless tuples.all? { |_, tuple| tuple['account_id'] == @account.id }

    started_at = Time.current
    client = JrcBroker::Context.new(account: @account, user: @user, release_connection: true).client
    raw = client.routing_context(@bindings.map(&:integration_id).uniq.sort)
    return {} unless valid_response?(raw, integration, started_at)
    return {} unless integration.reload.attributes.slice(*snapshot.keys) == snapshot
    return {} unless current_tuples(tuples) == tuples.sort_by { |model, tuple| [model.name, tuple['id']] }

    raw['data'].to_h { |row| [row['inboxId'], row['state']] }
  rescue JrcBroker::Client::Error, JrcBroker::Configuration::InvalidConfiguration, JrcBroker::CredentialStore::InvalidCredential,
         ActiveRecord::RecordNotFound, ArgumentError, TypeError
    {}
  end

  private

  def current_tuples(tuples)
    ApplicationRecord.uncached do
      tuples.group_by(&:first).flat_map do |model, entries|
        model.where(account_id: @account.id, id: entries.map { |_, tuple| tuple['id'] }).map do |record|
          [model, record.attributes.slice(*TUPLE_FIELDS)]
        end
      end.sort_by { |model, tuple| [model.name, tuple['id']] }
    end
  end

  def valid_response?(raw, integration, started_at)
    return false unless raw.is_a?(Hash) && raw.values_at('schemaVersion', 'organizationId', 'accountId', 'destinationRevision') ==
                        [1, integration.organization_id, @account.id, integration.destination_revision]
    return false unless raw['checkedAt'].is_a?(String)

    observed = Time.iso8601(raw['checkedAt'])
    return false unless observed >= started_at - 5.seconds && observed <= Time.current + 5.seconds

    rows = raw['data']
    expected = @bindings.map { |binding| [binding.integration_id, binding.inbox_id] }.uniq.sort
    return false unless rows.is_a?(Array) && rows.size == expected.size && rows.all? { |row| valid_row?(row) }

    rows.map { |row| [row['integrationId'], row['inboxId']] }.sort == expected
  end

  def valid_row?(row)
    row.is_a?(Hash) && row['integrationId'].is_a?(String) && JrcBroker::Client::UUID.match?(row['integrationId']) &&
      row['channelId'].is_a?(String) && JrcBroker::Client::UUID.match?(row['channelId']) &&
      row['inboxId'].is_a?(Integer) && row['inboxId'].positive? && %w[NONE ROUTED UNKNOWN].include?(row['state']) &&
      valid_revision?(row['ownerRevision'], 0) && valid_revision?(row['bindingRevision'], 1) &&
      @bindings.all? { |binding| binding.inbox_id != row['inboxId'] || !binding.respond_to?(:channel_id) || binding.channel_id == row['channelId'] }
  end

  def valid_revision?(value, minimum)
    value.nil? || (value.is_a?(Integer) && value >= minimum)
  end
end
