# frozen_string_literal: true

# Bounded recovery of already persisted unfinished work only. Terminal failures
# and blocked attempts are never retried automatically, and deactivation is
# rechecked by the same original-actor executor. No periodic schedule is added.
class JrcContactCenter::EndingAttemptReconcileJob < ApplicationJob
  queue_as :default

  def perform(account_id, after_id = 0)
    account = Account.find(account_id)
    return unless account.active? && account.feature_enabled?('jrc_contact_center')

    finished = JrcContactCenter::EndingActionAttemptOutcome.where(account: account).select(:attempt_id)
    rows = JrcContactCenter::EndingActionAttempt.where(account: account)
    rows = rows.where.not(id: finished).where('id > ?', Integer(after_id)).order(:id).limit(100)
    rows.each { |row| JrcContactCenter::EndingActions::ExecuteAttempt.new(account: account, attempt_id: row.id).call }
    rows.last&.id
  end
end
