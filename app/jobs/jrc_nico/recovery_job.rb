class JrcNico::RecoveryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    accounts = Account.where(id: JrcNico::Run.where('reserved_tokens > 0 OR status IN (?)', %w[queued running]).select(:account_id))
                      .or(Account.where(id: JrcNico::Inference.where('reserved_tokens > 0 OR status = ?', 'running').select(:account_id)))
    accounts.find_each { |account| JrcNico::ReservationReconciler.new(account: account).call(dry_run: false) }
    JrcNico::Run.where(status: 'queued').where('created_at < ?', 2.minutes.ago).find_each do |run|
      JrcNico::AnalyzeJob.perform_later(run.id)
    end
    JrcNico::BrokerSendOperation.where(state: JrcNico::BrokerSendOperation::ACTIVE_STATES)
      .where('next_attempt_at <= ? AND (lease_expires_at IS NULL OR lease_expires_at <= ?)', Time.current, Time.current)
      .order(:next_attempt_at, :id).limit(100).pluck(:id).each { |id| JrcNico::BrokerSendJob.perform_later(id) }
  end
end
