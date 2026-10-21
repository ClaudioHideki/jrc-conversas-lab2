class JrcCampaigns::BrokerConnector
  PROTOCOL = 'chatwoot-campaigns/v1'.freeze
  REASONS = %w[CAMPAIGN_BROKER_TRANSPORT_REQUIRED CAMPAIGN_EXECUTOR_EXTERNAL_REQUIRED CAMPAIGN_CALLBACK_NOT_READY CAMPAIGN_IDENTITY_NOT_READY].freeze
  attr_reader :inbox, :binding, :integration

  def self.for(inbox)
    return unless inbox&.channel_type == 'Channel::Api'
    return unless JrcBroker::Configuration.enabled? && inbox.account.feature_enabled?('jrc_broker')

    binding = JrcBrokerInboxBinding.find_by(account_id: inbox.account_id, inbox_id: inbox.id)
    integration = JrcBrokerIntegration.find_by(account_id: inbox.account_id)
    new(inbox, binding, integration) if binding && integration
  end

  def self.candidate?(inbox)
    return false unless inbox.channel_type == 'Channel::Api'
    return true if JrcBrokerInboxBinding.exists?(account_id: inbox.account_id, inbox_id: inbox.id)

    uri = URI.parse(inbox.channel.webhook_url.to_s)
    # A recognizable callback is only a setup candidate. It never grants sending authority.
    uri.is_a?(URI::HTTPS) && %r{\A/v1/integrations/chatwoot/[0-9a-f-]{36}/events\z}i.match?(uri.path)
  rescue URI::InvalidURIError
    false
  end

  def initialize(inbox, binding, integration)
    @inbox, @binding, @integration = inbox, binding, integration
  end

  def public_configuration
    { 'inbox_id' => inbox.id, 'integration_id' => binding.integration_id, 'instance_id' => binding.instance_id,
      'origin' => integration.broker_origin, 'organization_id' => integration.organization_id,
      'destination_revision' => integration.destination_revision, 'binding_revision' => binding.updated_at.iso8601(6),
      'configuration_revision' => integration.updated_at.iso8601(6) }
  end

  def context(user)
    JrcBroker::Context.new(account: inbox.account, user: user)
  end

  def transport(user)
    expected = "#{integration.broker_origin}/v1/integrations/chatwoot/#{binding.integration_id}/events"
    raise JrcBroker::Client::Error, 'JRC_BROKER_CALLBACK_MISMATCH' unless inbox.channel.webhook_url == expected

    data = context(user).client.campaign_transport(binding.integration_id)
    valid = data['protocol'] == PROTOCOL && data.values_at('integrationId', 'inboxId', 'instanceId', 'destinationRevision') ==
      [binding.integration_id, inbox.id, binding.instance_id, integration.destination_revision]
    valid &&= [true, false].include?(data['ready']) && data['identityRevision'].is_a?(Integer) && data['identityRevision'] >= 0
    valid &&= data['numberSuffix'].nil? || /\A\d{4}\z/.match?(data['numberSuffix'].to_s)
    valid &&= data['ready'] ? data['reason'].nil? : REASONS.include?(data['reason'])
    valid &&= data['identityRevision'].positive? if data['ready'] == true && valid
    raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE' unless valid

    data
  end

  def ready!(user)
    # Status refreshes the existing identity evidence; the scoped transport endpoint is read-only.
    context(user).client.status(binding.integration_id)
    data = transport(user)
    raise ArgumentError, "Broker indisponível para campanhas: #{data['reason']}" unless data['ready'] == true

    data
  end

  def receipt(user, conversation_id, message_id)
    data = context(user).client.campaign_receipt(binding.integration_id, conversation_id, message_id)
    valid = data['protocol'] == PROTOCOL && data.values_at('integrationId', 'conversationId', 'messageId') ==
      [binding.integration_id, conversation_id, message_id] && %w[queued sent delivered read failed blocked unknown].include?(data['status'])
    raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE' unless valid

    data['status']
  end
end
