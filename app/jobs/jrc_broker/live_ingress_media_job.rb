class JrcBroker::LiveIngressMediaJob < ApplicationJob
  queue_as :low

  def perform(id)
    receipt = JrcBrokerLiveReceipt.find_by(id: id, state: 'MEDIA_PENDING')
    return unless receipt

    receiver = receipt.receiver
    receiver.with_scope(receipt.inbox_id, receipt.envelope) { |_scope| nil }
    JrcBroker::LiveIngressMedia.new.store!(receipt)
    receiver.with_scope(receipt.inbox_id, receipt.envelope) do |scope|
      JrcBroker::IngressIdentity.lock!(scope, receipt.envelope)
      current = JrcBrokerLiveReceipt.lock.find(id)
      next unless current.state == 'MEDIA_PENDING'

      message = receiver.publish!(scope, current.envelope, current.blob)
      current.update!(state: 'PERSISTED', message: message, staged_bytes: nil, last_error: nil, published_at: Time.current)
    end
  rescue StandardError => e
    retry_receipt!(id, e)
  end

  private

  def retry_receipt!(id, error)
    # Neutral diagnostics only. Escrow and reserved object survive all failures;
    # the durable scheduler, rather than a credential-bearing job, owns recovery.
    code = error.is_a?(ArgumentError) && error.message == 'JRC_INGRESS_LEGACY_UNPROVEN' ? error.message : 'JRC_LIVE_MEDIA_RETRY'
    JrcBrokerLiveReceipt.where(id: id, state: 'MEDIA_PENDING').update_all( # rubocop:disable Rails/SkipsModelValidations
      ['attempts=attempts+1,last_error=?,next_attempt_at=?', code, 1.minute.from_now]
    )
  end
end
