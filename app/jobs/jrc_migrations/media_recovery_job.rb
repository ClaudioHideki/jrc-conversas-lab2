# Reconcile only durable, server-generated import reservations. Retaining cleaned
# reservations also catches a late storage write after a disconnected uploader.
class JrcMigrations::MediaRecoveryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    candidates = JrcMigrations::MediaObject.where(status: %w[planned cleanup_required recovering cleaned])
                                           .where('checked_at IS NULL OR checked_at <= ?', 5.minutes.ago)
                                           .order(Arel.sql('checked_at ASC NULLS FIRST, id ASC')).limit(100)
    candidates.each do |media|
      JrcMigrations::MediaRecovery.sweep(media)
    rescue StandardError => e
      media.account.with_lock('FOR NO KEY UPDATE') do
        media.with_lock do
          media.update!(checked_at: Time.current, error_code: 'MEDIA_RECOVERY_RETRY_REQUIRED') unless media.status.in?(%w[attached kept])
        end
      end
      Rails.logger.error("migration_media_recovery_failed media=#{media.id} class=#{e.class.name}")
    end
  end
end
