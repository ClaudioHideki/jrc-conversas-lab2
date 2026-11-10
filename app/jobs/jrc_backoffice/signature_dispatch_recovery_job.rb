# Covers a stop after admission commit and before enqueue. Already claimed,
# uncertain or terminal deliveries belong to reconciliation, never to resend.
class JrcBackoffice::SignatureDispatchRecoveryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    consumed = JrcBackoffice::SignatureDeliveryEvent.where.not(kind: 'prepared').select(:delivery_id)
    JrcBackoffice::SignatureDelivery.where.not(id: consumed).find_each(batch_size: 100) do |delivery|
      JrcBackoffice::SignatureDispatchJob.perform_later(delivery.id)
    end
  end
end
