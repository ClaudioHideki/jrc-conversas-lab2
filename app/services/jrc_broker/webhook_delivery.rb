class JrcBroker::WebhookDelivery
  class Unavailable < StandardError
    def initialize
      super('JRC_BROKER_DELIVERY_UNAVAILABLE')
    end
  end

  class ContextChanged < StandardError
    def initialize
      super('JRC_BROKER_DELIVERY_CONTEXT_CHANGED')
    end
  end

  def self.for(payload, webhook_type)
    return unless webhook_type == :api_inbox_webhook && payload[:event] == 'message_created'

    message = Message.find_by(id: payload[:id], message_type: :outgoing, private: false)
    attributes = payload[:additional_attributes].to_h
    marked_message = message && message.additional_attributes.to_h['jrc_campaign_broker'] == true
    campaign = attributes['jrc_campaign_broker'] == true || marked_message
    bound = message && JrcBrokerInboxBinding.exists?(account_id: message.account_id, inbox_id: message.inbox_id)
    return unless campaign || bound

    new(message)
  end

  def initialize(message)
    @message = message
  end

  def validate!(url:, secret:, delivery_id:)
    raise ContextChanged unless @message
    @message.reload
    channel = @message.inbox.channel
    valid = channel.is_a?(Channel::Api) && channel.webhook_url == url && delivery_id.present? && secret.present? &&
            ActiveSupport::SecurityUtils.secure_compare(channel.secret.to_s, secret)
    raise ContextChanged unless valid
  end

  def retryable?(error)
    return error.status >= 500 || [408, 425, 429].include?(error.status) if error.is_a?(JrcBroker::Client::Error)
    return true if error.is_a?(SafeFetch::FetchError) || error.is_a?(Errno::ECONNREFUSED) || error.is_a?(Errno::ECONNRESET)
    return false unless error.is_a?(SafeFetch::HttpError)

    status = error.message[/\A(\d{3})\b/, 1].to_i
    [408, 425, 429].include?(status) || (500..599).cover?(status)
  end

  def prepare_campaign_intent!(payload)
    JrcCampaigns::BrokerIntentReservation.new(@message).prepare!(payload)
  end

  def handle_failure(error)
    return unless @message
    code = if error.is_a?(Unavailable) || error.is_a?(ContextChanged)
             error.message
           else
             'JRC_BROKER_DELIVERY_REJECTED'
           end
    # A late failed attempt must not overwrite delivery/read confirmation.
    Messages::StatusUpdateService.new(@message, 'failed', code).perform unless @message.reload.delivered? || @message.read?
    Rails.logger.warn("[JrcBroker::WebhookDelivery] #{code} message_id=#{@message.id}")
  end
end
