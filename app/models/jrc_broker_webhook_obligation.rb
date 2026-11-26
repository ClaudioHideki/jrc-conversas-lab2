class JrcBrokerWebhookObligation < ApplicationRecord
  belongs_to :account
  belongs_to :message

  def self.capture!(message)
    return unless eligible?(message)

    binding = JrcBrokerInboxBinding.find_by(account_id: message.account_id, inbox_id: message.inbox_id)
    channel = message.inbox.channel
    return unless binding && channel.is_a?(Channel::Api) && channel.webhook_url.present?

    identity = campaign_identity(message).fetch(:delivery_id) { SecureRandom.uuid }
    mark_pending!(message, binding, identity)
    create!(delivery_id: identity, account_id: message.account_id, message_id: message.id, inbox_id: message.inbox_id, binding_id: binding.id,
            integration_id: binding.integration_id, instance_id: binding.instance_id, url: channel.webhook_url,
            available_at: Time.current, payload: callback_payload(message))
  end

  def self.callback_payload(message)
    payload = message.webhook_data.merge(event: 'message_created')
    # A newly inserted conversation can still have a cached nil display_id
    # until Rails reads back the value allocated by PostgreSQL.
    payload[:conversation][:id] ||= Conversation.where(id: message.conversation_id, account_id: message.account_id, inbox_id: message.inbox_id)
                                                .pick(:display_id)
    payload
  end
  private_class_method :callback_payload

  def self.mark_pending!(message, binding, identity)
    outbound = { 'version' => 1, 'state' => 'PENDING', 'intent_id' => identity,
                 'integration_id' => binding.integration_id, 'inbox_id' => message.inbox_id }
    # This runs in the message creation transaction, before message_created is dispatched.
    message.update_columns(content_attributes: message.content_attributes.to_h.merge('jrc_broker_outbound' => outbound)) # rubocop:disable Rails/SkipsModelValidations
  end
  private_class_method :mark_pending!

  def self.campaign_identity(message)
    return {} unless message.additional_attributes['jrc_campaign_broker'] == true

    identity = message.additional_attributes['jrc_campaign_webhook_delivery_id']
    identity.present? ? { delivery_id: identity } : {}
  end
  private_class_method :campaign_identity

  def self.eligible?(message)
    deliverable_message?(message) && message.webhook_sendable? && message.additional_attributes['jrc_campaign_evolution'] != true
  end

  def self.deliverable_message?(message)
    native_csat = message.template? && message.input_csat? && message.sender_type.nil? && message.sender_id.nil?
    (message.outgoing? || native_csat) && !message.private?
  end

  def current_binding?
    JrcBrokerInboxBinding.uncached do
      JrcBrokerInboxBinding.exists?(id: binding_id, account_id: account_id, inbox_id: inbox_id,
                                    integration_id: integration_id, instance_id: instance_id) &&
        message.account_id == account_id && message.inbox_id == inbox_id && message.inbox.channel.webhook_url == url
    end
  end
end
