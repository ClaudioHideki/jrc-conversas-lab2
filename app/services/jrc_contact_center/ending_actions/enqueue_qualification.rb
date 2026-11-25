# frozen_string_literal: true

# Called after the real classification/completion commit. Broker failure must
# not undo ACW or lose the work: preserve technical attempts for reconciliation.
# No destination is executed by this fallback; raw exception text is not logged.
class JrcContactCenter::EndingActions::EnqueueQualification
  def self.call(account_id:, qualification_id:)
    job = JrcContactCenter::EndingActionsJob.perform_later(account_id, qualification_id)
    raise ActiveJob::EnqueueError, 'ending_automation_enqueue_unavailable' unless job

    true
  rescue StandardError
    preserve_pending_work(account_id, qualification_id)
    false
  end

  def self.preserve_pending_work(account_id, qualification_id)
    account = Account.find(account_id)
    return unless account.active? && account.feature_enabled?('jrc_contact_center')

    rows = JrcContactCenter::EndingActions::InitialProjectAttempts.new(account: account, qualification_id: qualification_id).call
    typed_rows = JrcContactCenter::EndingActions::InitialDestinationAttempts.new(account: account, qualification_id: qualification_id).call
    pending = rows.length + typed_rows.length
    Rails.logger.warn("ending_automation_enqueue_unavailable account_id=#{account_id} qualification_id=#{qualification_id} pending=#{pending}")
  rescue StandardError
    # The attested original remains durable even if the history database itself
    # is temporarily unavailable. Alert rather than claim execution or success.
    Rails.logger.error("ending_automation_recovery_required account_id=#{account_id} qualification_id=#{qualification_id}")
  end
  private_class_method :preserve_pending_work
end
