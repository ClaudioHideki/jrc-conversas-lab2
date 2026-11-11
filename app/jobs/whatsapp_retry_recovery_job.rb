class WhatsappRetryRecoveryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    WhatsappRetryAttempt.where(state: 'submitting').where('updated_at < ?', 10.minutes.ago).find_each do |candidate|
      reconcile = false
      WhatsappRetryAttempt.transaction do
        attempt = WhatsappRetryAttempt.where(id: candidate.id, state: 'submitting').where('updated_at < ?', 10.minutes.ago)
                                      .lock('FOR UPDATE SKIP LOCKED').first
        next unless attempt

        if attempt.message.source_id.present?
          reconcile = true
        else
          attempt.transition!('unknown')
        end
      end
      Whatsapp::RetryReceiptService.reconcile!(candidate) if reconcile
    end
    WhatsappRetryAttempt.where(state: 'unknown').joins(:message).where.not(messages: { source_id: [nil, ''] }).find_each do |attempt|
      Whatsapp::RetryReceiptService.reconcile!(attempt)
    end
    WhatsappRetryAttempt.where(state: 'queued').where('next_attempt_at IS NULL OR next_attempt_at <= ?', Time.current).find_each do |attempt|
      WhatsappRetryJob.perform_later(attempt.id)
    end
  end
end
