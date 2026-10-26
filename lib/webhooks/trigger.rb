class Webhooks::Trigger
  SUPPORTED_ERROR_HANDLE_EVENTS = %w[message_created message_updated].freeze
  RETRYABLE_AGENT_BOT_STATUSES = [429, 500].freeze

  class RetryableError < StandardError
    attr_reader :status

    def initialize(status:, message:)
      @status = status
      super(message)
    end
  end

  def initialize(url, payload, webhook_type, secret: nil, delivery_id: nil, campaign_recovery_token: nil)
    @url = url
    @payload = payload
    @webhook_type = webhook_type
    @secret = secret
    @delivery_id = delivery_id
    @campaign_recovery_token = campaign_recovery_token
  end

  def self.execute(url, payload, webhook_type, secret: nil, delivery_id: nil, campaign_recovery_token: nil)
    new(url, payload, webhook_type, secret: secret, delivery_id: delivery_id, campaign_recovery_token: campaign_recovery_token).execute
  end

  def execute
    if @webhook_type == :api_inbox_webhook && @payload[:event] == 'message_created' &&
       message && JrcRelationship::SurveyMessageExecution.applies?(message)
      JrcRelationship::SurveyMessageExecution.new(message).perform { execute_delivery }
    elsif @webhook_type == :api_inbox_webhook && @payload[:event] == 'message_created' &&
          message && message.content_attributes['service_desk_delivery_id']
      JrcServiceDesk::NotificationExecution.new(message).perform { execute_delivery }
    else
      execute_delivery
    end
  end

  def execute_delivery
    if @webhook_type == :api_inbox_webhook && @payload[:event] == 'message_created' && message
      JrcServiceDesk::OutboundAttachments.authorize_message!(message)
      if message.outgoing? && !message.private? && JrcServiceDesk::OutboundAttachments.protected?(message)
        message.update!(status: :failed, external_error: 'Protected Service Desk attachments require an authenticated media upload transport; API inbox URL delivery is unavailable')
        return
      end
    end
    return unless prepare_jrc_delivery

    body = @payload.to_json
    headers = request_headers(body)
    timeout = webhook_timeout
    @jrc_delivery_phase = 'callback'
    return unless start_jrc_callback

    perform_request(body: body, headers: headers, timeout: timeout)
    jrc_delivery&.callback_accepted!
  rescue StandardError => e
    handle_delivery_error(e)
  end

  private :execute_delivery

  def handle_failure(error)
    return jrc_delivery.handle_failure(error) if jrc_delivery

    handle_error(error)
    Rails.logger.warn "Webhook delivery failed (#{error.class.name})"
  end

  private

  def prepare_jrc_delivery
    @jrc_delivery_phase = 'validate'
    jrc_delivery&.validate!(url: @url, secret: @secret, delivery_id: @delivery_id)
    @jrc_delivery_phase = 'campaign_intent'
    return false if jrc_delivery&.prepare_campaign_intent!(@payload) == false
    @jrc_delivery_phase = 'validate'
    jrc_delivery&.validate!(url: @url, secret: @secret, delivery_id: @delivery_id)
    true
  end

  def start_jrc_callback
    return true unless jrc_delivery
    return jrc_delivery.callback_started! unless @campaign_recovery_token

    JrcCampaigns::BrokerRecoveryService.callback_allowed?(@payload, token: @campaign_recovery_token, start: true,
                                                                 callback: { url: @url, secret: @secret, delivery_id: @delivery_id })
  end

  def handle_delivery_error(error)
    jrc_delivery&.record_failure(error, phase: @jrc_delivery_phase)
    raise RetryableError.new(status: http_status(error), message: error.message) if retryable_agent_bot_error?(error)
    raise JrcBroker::WebhookDelivery::Unavailable if jrc_delivery&.retryable?(error)

    handle_failure(error)
  end

  def jrc_delivery
    return @jrc_delivery if defined?(@jrc_delivery)

    @jrc_delivery = JrcBroker::WebhookDelivery.for(@payload, @webhook_type)
  end

  def perform_request(body:, headers:, timeout:)
    if jrc_delivery
      pool = ActiveRecord::Base.connection_pool
      connection = pool.active_connection?
      pool.release_connection if connection && !connection.transaction_open?
    end
    SafeFetch.fetch(
      @url,
      method: :post,
      body: body,
      headers: headers,
      open_timeout: timeout,
      read_timeout: timeout,
      validate_content_type: false
    ) { |_response| nil }
  end

  def request_headers(body)
    headers = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
    headers['X-Chatwoot-Delivery'] = @delivery_id if @delivery_id.present?
    if @secret.present?
      ts = Time.now.to_i.to_s
      headers['X-Chatwoot-Timestamp'] = ts
      headers['X-Chatwoot-Signature'] = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', @secret, "#{ts}.#{body}")}"
    end
    headers
  end

  def handle_error(error)
    return unless SUPPORTED_ERROR_HANDLE_EVENTS.include?(@payload[:event])
    return unless message

    case @webhook_type
    when :agent_bot_webhook
      update_conversation_status(message)
    when :api_inbox_webhook
      update_message_status(error)
    end
  end

  def update_conversation_status(message)
    conversation = message.conversation
    return unless conversation&.pending?
    return if conversation&.account&.keep_pending_on_bot_failure

    conversation.open!
    create_agent_bot_error_activity(conversation)
  end

  def create_agent_bot_error_activity(conversation)
    content = I18n.t('conversations.activity.agent_bot.error_moved_to_open')
    Conversations::ActivityMessageJob.perform_later(conversation, activity_message_params(conversation, content))
  end

  def activity_message_params(conversation, content)
    {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: content
    }
  end

  def update_message_status(error)
    Messages::StatusUpdateService.new(message, 'failed', error.message).perform
  end

  def message
    return if message_id.blank?

    if defined?(@message)
      @message
    else
      @message = Message.find_by(id: message_id)
    end
  end

  def message_id
    @payload[:id]
  end

  def webhook_timeout
    raw_timeout = GlobalConfig.get_value('WEBHOOK_TIMEOUT')
    timeout = raw_timeout.presence&.to_i

    timeout&.positive? ? timeout : 5
  end

  def retryable_agent_bot_error?(error)
    @webhook_type == :agent_bot_webhook && RETRYABLE_AGENT_BOT_STATUSES.include?(http_status(error))
  end

  def http_status(error)
    return unless error.is_a?(SafeFetch::HttpError)

    error.message.to_s[/\A(\d{3})\b/, 1]&.to_i
  end
end
