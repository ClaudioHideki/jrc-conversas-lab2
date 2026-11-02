class JrcBrokerWebhookObligation < ApplicationRecord
  belongs_to :account
  belongs_to :message

  def self.capture!(message)
    return unless eligible?(message)

    binding = JrcBrokerInboxBinding.find_by(account_id: message.account_id, inbox_id: message.inbox_id)
    channel = message.inbox.channel
    return unless binding && channel.is_a?(Channel::Api) && channel.webhook_url.present?

    callback_id = message.additional_attributes['jrc_campaign_webhook_delivery_id'] if message.additional_attributes['jrc_campaign_broker'] == true
    identity = callback_id.present? ? { delivery_id: callback_id } : {}
    create!(**identity, account_id: message.account_id, message_id: message.id, inbox_id: message.inbox_id, binding_id: binding.id,
            integration_id: binding.integration_id, instance_id: binding.instance_id, url: channel.webhook_url,
            payload: message.webhook_data.merge(event: 'message_created'))
  end

  def self.eligible?(message)
    message.outgoing? && !message.private? && message.webhook_sendable? && message.additional_attributes['jrc_campaign_evolution'] != true
  end

  def current_binding?
    JrcBrokerInboxBinding.uncached do
      JrcBrokerInboxBinding.exists?(id: binding_id, account_id: account_id, inbox_id: inbox_id,
                                    integration_id: integration_id, instance_id: instance_id) &&
        message.account_id == account_id && message.inbox_id == inbox_id && message.inbox.channel.webhook_url == url
    end
  end
end
