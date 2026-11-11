class WhatsappRetryJob < ApplicationJob
  queue_as :high

  def perform(attempt_id)
    attempt = WhatsappRetryAttempt.find_by(id: attempt_id)
    Whatsapp::RetryDeliveryService.new(attempt).perform if attempt
  end
end
