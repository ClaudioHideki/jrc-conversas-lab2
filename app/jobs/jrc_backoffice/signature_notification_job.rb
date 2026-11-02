class JrcBackoffice::SignatureNotificationJob < ApplicationJob
  queue_as :low
  retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(receipt_id)
    JrcBackoffice::Signatures::Notifications.new(receipt_id: receipt_id).call
  rescue JrcBackoffice::Signatures::ProviderError, JrcBackoffice::Signatures::DeliveryError => e
    JrcBackoffice::SignatureNotification.find(receipt_id).update!(state: 'failed')
    Rails.logger.warn("[SignatureNotification] receipt_id=#{receipt_id} code=#{e.code}")
  end
end
