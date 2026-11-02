# Durable proof that this canonical callback has not crossed the provider boundary.
class JrcCampaigns::BrokerCallbackDeferral
  KEY = 'broker_callback_deferred'.freeze

  def self.marker(message_id:, webhook_delivery_id:, reason:, wait_until: nil)
    { 'version' => 1, 'message_id' => message_id, 'webhook_delivery_id' => webhook_delivery_id,
      'reason' => reason, 'until' => wait_until&.iso8601 }
  end

  def self.mark!(delivery, message:, reason:, wait_until: nil)
    return false unless delivery.is_a?(JrcCampaigns::Delivery)

    delivery.with_lock do
      message.with_lock do
        next false unless pre_callback?(delivery, message)

        JrcCampaigns::BrokerRecoveryService.enqueue_watchdog(delivery.id, delivery.metadata['dispatch_token'], wait_until: wait_until) if wait_until
        data = marker(message_id: message.id, webhook_delivery_id: delivery.metadata['webhook_delivery_id'], reason: reason, wait_until: wait_until)
        delivery.update!(metadata: delivery.metadata.to_h.merge(KEY => data))
        true
      end
    end
  end

  def self.pending?(delivery)
    with_marker(delivery) { |message, _marker| delivery.sending? && known_unsent?(delivery, message) }
  end

  def self.hold?(delivery)
    with_marker(delivery) do |message, marker|
      state = delivery.sending? || (delivery.skipped? && marker['reason'] == 'skipped')
      state && known_unsent?(delivery, message)
    end
  end

  def self.with_marker(delivery)
    return false unless delivery.is_a?(JrcCampaigns::Delivery)

    delivery.with_lock do
      marker = delivery.metadata[KEY]
      next false unless marker.is_a?(Hash) && marker['version'] == 1
      next false unless marker.values_at('message_id', 'webhook_delivery_id') == delivery.metadata.values_at('message_id', 'webhook_delivery_id')

      message = delivery.inbox.account.messages.find_by(id: marker['message_id'], inbox_id: delivery.inbox_id)
      message ? message.with_lock { yield message, marker } : false
    end
  end

  # Called under delivery/message locks, before writing callback_started!. On queue
  # failure the safe marker and the existing watchdog remain available for recovery.
  def self.resume_polling(delivery)
    !!JrcCampaigns::BrokerStatusJob.set(wait: 10.seconds).perform_later('campaign', delivery.id)
  rescue StandardError
    false
  end

  def self.clear!(delivery)
    return unless delivery.metadata.key?(KEY)

    marker = delivery.metadata[KEY]
    attributes = { metadata: delivery.metadata.to_h.except(KEY) }
    attributes[:error_message] = nil if marker.is_a?(Hash) && marker['reason'] == 'blocked'
    delivery.update!(attributes)
    delivery.recipient.update!(error_message: nil) if attributes.key?(:error_message)
  end

  def self.pre_callback?(delivery, message)
    delivery.sending? && known_unsent?(delivery, message)
  end

  def self.known_unsent?(delivery, message)
    delivery.sent_at.nil? && !message.failed? && same_route?(delivery, message) && same_message?(delivery, message) &&
      JrcBroker::WebhookDiagnostic.pre_callback?(JrcBroker::WebhookDiagnostic.new(message).read)
  end

  def self.same_route?(delivery, message)
    [delivery.inbox.account_id, delivery.inbox_id, delivery.metadata['message_id'], delivery.metadata['conversation_id'], delivery.external_id] ==
      [message.account_id, message.inbox_id, message.id, message.conversation.display_id,
       "broker:#{message.account_id}:#{message.inbox_id}:#{message.id}"]
  end

  def self.same_message?(delivery, message)
    attrs = message.additional_attributes.to_h
    uuid = delivery.metadata['webhook_delivery_id']
    uuid.present? && [message.message_type, message.private?, attrs['jrc_campaign_broker'], attrs['campaign_id'].to_s,
                      attrs['jrc_campaign_broker_delivery_id'], attrs['jrc_campaign_webhook_delivery_id']] ==
      ['outgoing', false, true, delivery.recipient.campaign_id.to_s, delivery.id, uuid]
  end

  private_class_method :with_marker, :pre_callback?, :known_unsent?, :same_route?, :same_message?
end
