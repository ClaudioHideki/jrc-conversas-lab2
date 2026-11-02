# frozen_string_literal: true

# Locally verified native API-inbox binding. This is not campaign eligibility
# and does not query the provider or grant inbox access to an executor.
class JrcBroker::OutboundChannel
  def self.configuration(inbox)
    return unless inbox&.channel_type == 'Channel::Api'
    return unless JrcBroker::Configuration.enabled? && inbox.account.feature_enabled?('jrc_broker')

    binding = JrcBrokerInboxBinding.find_by(account_id: inbox.account_id, inbox_id: inbox.id)
    integration = JrcBrokerIntegration.find_by(account_id: inbox.account_id)
    return unless binding && integration

    origin = JrcBroker::Configuration.allowed_origin!(integration.broker_origin)
    expected = "#{origin}/v1/integrations/chatwoot/#{binding.integration_id}/events"
    return unless inbox.channel.webhook_url == expected && inbox.channel.secret.present?

    { 'integration_id' => binding.integration_id, 'instance_id' => binding.instance_id,
      'destination_revision' => integration.destination_revision,
      'binding_revision' => binding.updated_at.iso8601(6), 'configuration_revision' => integration.updated_at.iso8601(6) }
  rescue JrcBroker::Configuration::InvalidConfiguration
    nil
  end

  def self.available?(inbox)
    configuration(inbox).present?
  end
end
