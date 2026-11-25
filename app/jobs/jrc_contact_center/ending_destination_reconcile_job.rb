# frozen_string_literal: true

# Existing reconciliation pattern, restricted to typed, unfinished attempts.
# No account scan, terminal retry, historical backfill or periodic schedule.
class JrcContactCenter::EndingDestinationReconcileJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(account_id, after_id = 0)
    account = Account.find(JrcServiceDesk::Input.id(account_id))
    finished = JrcContactCenter::EndingDestinationOutcome.where(account: account).select(:attempt_id)
    rows = JrcContactCenter::EndingDestinationAttempt.where(account: account).where.not(id: finished)
    rows = rows.where('id > ?', Integer(after_id)).order(:id).limit(100)
    rows.each do |row|
      JrcContactCenter::EndingActions::ExecuteDestinationAttempt.new(account: account, attempt_id: row.id).call
    end
    rows.last&.id
  end
end
