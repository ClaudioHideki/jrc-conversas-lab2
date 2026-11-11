class Whatsapp::RetryDeliveryService
  def initialize(attempt)
    @attempt = attempt
  end

  def perform
    claimed = @attempt.with_lock do
      next false unless @attempt.state == 'queued'
      unless locally_allowed?
        @attempt.transition!('cancelled')
        next false
      end
      @attempt.transition!('submitting')
      true
    end
    return unless claimed

    templates = current_templates
    unless templates && locally_allowed? &&
           Whatsapp::RetryPolicy.valid_template?(@attempt.message.additional_attributes['template_params'], templates)
      return finish('cancelled')
    end

    child = @attempt.message.reload
    # Use the currently approved provider template without changing channel configuration.
    child.conversation.inbox.channel.message_templates = templates
    @submission_started = true
    Whatsapp::SendOnWhatsappService.new(message: child).perform
    @attempt.inbox.channel.with_lock do
      @attempt.lock!
      child.reload
      if child.source_id.present?
        @attempt.transition!('accepted') if %w[submitting unknown].include?(@attempt.state)
        WhatsappRetryReceipt.where(inbox_id: @attempt.inbox_id, source_id: child.source_id)
                            .order(Arel.sql("CASE status WHEN 'sent' THEN 0 WHEN 'failed' THEN 1 WHEN 'delivered' THEN 2 ELSE 3 END")).each do |receipt|
          receipt.update!(whatsapp_retry_attempt: @attempt)
          Whatsapp::RetryReceiptService.apply!(@attempt, receipt.status, receipt.error_code)
        end
      elsif child.external_error.to_s.match?(/\A\d{1,9}:/)
        @attempt.transition!('failed', error_code: child.external_error[/\A\d{1,9}/])
      else
        @attempt.transition!('unknown')
      end
    end
  rescue StandardError => e
    Rails.logger.warn("WhatsApp retry attempt=#{@attempt.id} error=#{e.class.name}")
    finish(@submission_started ? 'unknown' : 'cancelled') if claimed
  end

  private

  def locally_allowed?
    original = @attempt.original_message.reload
    child = @attempt.message.reload
    Whatsapp::RetryPolicy.reason(original, @attempt.actor, cooldown: false).nil? &&
      Whatsapp::RetryPolicy.fingerprint(original) == @attempt.payload_fingerprint &&
      child.content == original.content && child.additional_attributes['template_params'] == original.additional_attributes['template_params'] &&
      !child.private? && child.content_attributes.except('external_error') == original.content_attributes.except('external_error')
  end

  def current_templates
    channel = @attempt.inbox.channel
    config = channel.provider_config
    return if config.values_at('api_key', 'phone_number_id', 'business_account_id').any?(&:blank?)

    name = @attempt.message.additional_attributes.dig('template_params', 'name')
    response = HTTParty.get(
      "#{ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')}/v14.0/#{config['business_account_id']}/message_templates",
      headers: channel.api_headers, query: { name: name, limit: 100 }, timeout: 15
    )
    return unless response.success? && response.parsed_response.is_a?(Hash)

    response.parsed_response['data']
  end

  def finish(state)
    @attempt.with_lock do
      @attempt.transition!(state) if %w[submitting unknown].include?(@attempt.state)
    end
  end
end
