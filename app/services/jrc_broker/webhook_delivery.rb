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

  def callback_started!
    diagnostic.callback_started!
  end

  def callback_accepted!
    diagnostic.callback_accepted!
  end

  def record_failure(error, phase:)
    diagnostic.failure!(error, phase: phase)
  end

  def handle_failure(error)
    return unless @message

    diagnostic.failure!(error) if diagnostic.read.empty?
    code = failure_code(error)
    mark_failure(code)
    Rails.logger.warn({ event: 'jrc_broker_webhook_failure', code: code, message_id: @message.id,
                        **diagnostic.read.slice('phase', 'error_class', 'http_status', 'outcome') }.to_json)
  end

  private

  def failure_code(error)
    return 'JRC_BROKER_DELIVERY_UNAVAILABLE' if error.is_a?(Unavailable)
    return 'JRC_BROKER_DELIVERY_CONTEXT_CHANGED' if error.is_a?(ContextChanged)

    'JRC_BROKER_DELIVERY_REJECTED'
  end

  def mark_failure(code)
    # A late failed attempt must not overwrite delivery/read confirmation.
    return if JrcCampaigns::BrokerDeliveryFailure.call(message: @message, failure_code: code) || @message.reload.delivered? || @message.read?

    Messages::StatusUpdateService.new(@message, 'failed', code).perform
  end

  def diagnostic
    @diagnostic ||= JrcBroker::WebhookDiagnostic.new(@message)
  end
end
