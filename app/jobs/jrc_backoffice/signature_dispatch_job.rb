# The only job argument is a committed internal intent ID, never provider or
# tenant parameters. Dispatch claims once; an uncertain POST is not resent.
class JrcBackoffice::SignatureDispatchJob < ApplicationJob
  queue_as :low
  retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(delivery_id)
    JrcBackoffice::Signatures::Dispatch.new(delivery_id: delivery_id).call
  end
end
