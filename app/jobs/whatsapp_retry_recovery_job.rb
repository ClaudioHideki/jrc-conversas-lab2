class WhatsappRetryRecoveryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    WhatsappRetryAttempt.where(state: 'submitting').where('updated_at < ?', 10.minutes.ago).find_each do |attempt|
      attempt.with_lock { attempt.transition!('unknown') if attempt.state == 'submitting' && attempt.updated_at < 10.minutes.ago }
    end
    WhatsappRetryAttempt.where(state: 'queued').find_each { |attempt| WhatsappRetryJob.perform_later(attempt.id) }
  end
end
