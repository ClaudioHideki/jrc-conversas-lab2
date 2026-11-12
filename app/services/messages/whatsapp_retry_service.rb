class Messages::WhatsappRetryService
  def initialize(message:, actor:)
    @message = message
    @actor = actor
  end

  def perform
    attempt = nil
    reason = nil
    repeated = false
    @message.with_lock do
      attempt = WhatsappRetryAttempt.find_by(original_message_id: @message.id)
      if attempt
        repeated = true
      else
        reason = Whatsapp::RetryPolicy.reason(@message, @actor)
        next if reason

        child = @message.conversation.messages.create!(
          account: @message.account, inbox: @message.inbox, sender: @actor, message_type: :outgoing,
          status: :failed, content: @message.content, content_type: @message.content_type,
          content_attributes: @message.content_attributes.except('external_error'),
          additional_attributes: { 'template_params' => @message.additional_attributes['template_params'],
                                   'whatsapp_retry' => { 'original_message_id' => @message.id, 'state' => 'queued' } }
        )
        attempt = WhatsappRetryAttempt.create!(
          account: @message.account, inbox: @message.inbox, actor: @actor, original_message: @message, message: child,
          prior_error_code: Whatsapp::RetryPolicy.error_code(@message), policy_version: Whatsapp::RetryPolicy::VERSION,
          payload_fingerprint: Whatsapp::RetryPolicy.fingerprint(@message)
        )
        attempt.transition!('queued')
      end
    end
    return { status: 'blocked', reason: reason, message_id: @message.id, error_code: Whatsapp::RetryPolicy.error_code(@message) } if reason

    enqueue(attempt) unless repeated
    { status: repeated ? 'already_requested' : 'queued', attempt_id: attempt.id, original_message_id: @message.id,
      message_id: attempt.message_id, state: attempt.reload.state }
  end

  private

  def enqueue(attempt)
    WhatsappRetryJob.perform_later(attempt.id)
  rescue StandardError => e
    # The committed queued row is the outbox obligation; the recovery job will enqueue it.
    Rails.logger.warn("WhatsApp retry enqueue pending attempt=#{attempt.id} error=#{e.class.name}")
  end
end
