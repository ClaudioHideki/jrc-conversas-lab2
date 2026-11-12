# No POST or envelope replacement: this job only reconciles an existing claim.
class JrcBackoffice::SignatureReconciliationJob < ApplicationJob
  queue_as :low
  retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(delivery_id)
    JrcBackoffice::Signatures::Reconciliation.new(delivery_id: delivery_id).call
  end
end
