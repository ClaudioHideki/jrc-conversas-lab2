class Whatsapp::RetryDeliveryService
  def initialize(attempt)
    @attempt = attempt
  end

  def perform
    return unless @attempt.state == 'queued' && due?
    return cancel_queued unless locally_allowed?

    templates = current_templates
    return defer_validation if templates == :unavailable
    unless templates.is_a?(Array) &&
           Whatsapp::RetryPolicy.valid_template?(@attempt.message.additional_attributes['template_params'], templates)
      return cancel_queued
    end

    # Read-only validation can repeat; commit the claim only when ready for POST.
    claimed = @attempt.with_lock do
      next false unless @attempt.state == 'queued' && due?
      unless locally_allowed?
        @attempt.transition!('cancelled')
        next false
      end
      @attempt.update!(next_attempt_at: nil)
      @attempt.transition!('submitting')
      true
    end
    return unless claimed

    # Protect the committed claim during I/O. Recovery skips this locked row.
    # Never acquire a channel lock here: receipt finalization uses channel -> attempt.
    dispatched = @attempt.with_lock do
      next false unless @attempt.state == 'submitting'
      unless locally_allowed?
        @attempt.transition!('cancelled')
        next false
      end
      child = @attempt.message.reload
      child.conversation.inbox.channel.message_templates = templates
      params = child.additional_attributes['template_params']
      template = templates.find { |item| item['name'] == params['name'] && item['language'] == params['language'] }
      unless template['parameter_format'] == 'NAMED'
        params['processed_params']['body'] = params['processed_params'].fetch('body', {}).sort_by { |key, _value| key.to_i }.to_h
      end
      @submission_started = true
      Whatsapp::SendOnWhatsappService.new(message: child).perform
      true
    end
    return unless dispatched

    child = @attempt.message.reload
    if child.source_id.present?
      Whatsapp::RetryReceiptService.reconcile!(@attempt)
    elsif child.external_error.to_s.match?(/\A\d{1,9}:/)
      finish('failed', error_code: child.external_error[/\A\d{1,9}/])
    else
      finish('unknown')
    end
  rescue StandardError => e
    Rails.logger.warn("WhatsApp retry attempt=#{@attempt.id} error=#{e.class.name}")
    @submission_started ? finish('unknown') : defer_validation
  end

  private

  def due?
    @attempt.next_attempt_at.nil? || @attempt.next_attempt_at <= Time.current
  end

  def locally_allowed?
    original = @attempt.original_message.reload
    child = @attempt.message.reload
    Whatsapp::RetryPolicy.reason(original, @attempt.actor, cooldown: false).nil? &&
      Whatsapp::RetryPolicy.fingerprint(original) == @attempt.payload_fingerprint &&
      child.content == original.content && child.content_type == original.content_type && child.outgoing? &&
      child.source_id.blank? && !child.private? &&
      child.additional_attributes['template_params'] == original.additional_attributes['template_params'] &&
      child.content_attributes.except('external_error') == original.content_attributes.except('external_error')
  end

  def current_templates
    channel = @attempt.inbox.channel
    config = channel.provider_config
    return :rejected if config.values_at('api_key', 'phone_number_id', 'business_account_id').any?(&:blank?)

    name = @attempt.message.additional_attributes.dig('template_params', 'name')
    response = HTTParty.get(
      "#{ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')}/v14.0/#{config['business_account_id']}/message_templates",
      headers: channel.api_headers, query: { name: name, limit: 100 }, timeout: 15
    )
    return :unavailable if response.code.to_i >= 500 || [408, 429].include?(response.code.to_i)
    return :rejected unless response.success?
    return :unavailable unless response.parsed_response.is_a?(Hash) && response.parsed_response['data'].is_a?(Array)

    response.parsed_response['data']
  end

  def defer_validation
    @attempt.with_lock do
      next unless @attempt.state == 'queued'

      failures = @attempt.validation_failures + 1
      delay = [60 * (2**[failures - 1, 4].min), 900].min
      @attempt.update!(validation_failures: failures, next_attempt_at: delay.seconds.from_now)
      @attempt.transition!('queued')
    end
  end

  def cancel_queued
    @attempt.with_lock { @attempt.transition!('cancelled') if @attempt.state == 'queued' }
  end

  def finish(state, error_code: nil)
    @attempt.with_lock do
      @attempt.transition!(state, error_code: error_code) if %w[submitting unknown].include?(@attempt.state)
    end
  end
end
