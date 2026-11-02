# Receipts can precede a provider acknowledgement or queue availability. Only
# exactly bound receipts are retried here; unrelated/legacy inboxes stay intact.
class JrcBackoffice::SignatureNotificationRecoveryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    rows = JrcBackoffice::SignatureNotification.where(state: 'received').joins(<<~SQL.squish)
      INNER JOIN jrc_backoffice_signature_delivery_events binding
      ON binding.external_id = jrc_backoffice_signature_notifications.envelope_id
      AND binding.connection_id = jrc_backoffice_signature_notifications.connection_id
      AND binding.account_id = jrc_backoffice_signature_notifications.account_id
      AND binding.kind = 'send_confirmed'
    SQL
    rows.order(:id).limit(100).pluck(:id).each { |id| JrcBackoffice::SignatureNotificationJob.perform_later(id) }
  end
end
