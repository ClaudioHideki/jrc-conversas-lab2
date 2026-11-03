class JrcBackoffice::SignatureNotificationJob < ApplicationJob
  queue_as :low
  retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(receipt_id)
    processor = JrcBackoffice::Signatures::Notifications.new(receipt_id: receipt_id)
    result = processor.call
    return unless processor.delivery && result.in?(%i[processed finished])

    # Fact consumption committed before projection. A retry reuses the same
    # authenticated binding; it neither duplicates the fact nor resends a PDF.
    JrcBackoffice::Signatures::DeliveryProjection.call(processor.delivery)
  rescue JrcBackoffice::Signatures::ProviderError, JrcBackoffice::Signatures::DeliveryError => e
    JrcBackoffice::SignatureNotification.find(receipt_id).update!(state: 'failed')
    Rails.logger.warn("[SignatureNotification] receipt_id=#{receipt_id} code=#{e.code}")
  end
end
