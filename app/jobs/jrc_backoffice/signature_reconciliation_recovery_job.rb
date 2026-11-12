class JrcBackoffice::SignatureReconciliationRecoveryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    JrcBackoffice::Signatures::Reconciliation.candidates.pluck(:id).each do |id|
      JrcBackoffice::SignatureReconciliationJob.perform_later(id)
    end
  end
end
