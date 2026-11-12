class JrcApprovals::NotificationRecoveryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    JrcApprovals::DelegationExpiryNotifications.call
    count = 0
    Account.where(id: pending.select(:account_id)).find_each do |account|
      next unless account.active? && account.feature_enabled?('jrc_approvals')

      ids = pending.where(account_id: account.id).order(:id).limit(100 - count).pluck(:source_event_id)
      ids.each { |id| JrcApprovals::NotificationProjectionJob.perform_later(id) }
      count += ids.size
      break if count >= 100
    end
  end

  private

  def pending
    JrcApprovals::NotificationOutbox.where(completed_at: nil)
  end
end
