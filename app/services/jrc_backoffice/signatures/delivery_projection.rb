# The immutable outcome is already committed before this operational view is
# updated. A projection conflict cannot erase an acknowledged external send.
class JrcBackoffice::Signatures::DeliveryProjection
  def self.call(delivery)
    return delivery unless delivery.state.in?(%w[sent completion_reported])

    id = delivery.external_id
    return delivery unless id

    delivery.contract.with_lock('FOR NO KEY UPDATE') do
      contract = delivery.contract
      check_reference!(contract, id)
      next delivery if contract.signature_status == 'signed'

      fields = { signature_mode: 'provider', signature_provider: delivery.snapshot.fetch('provider'),
                 signature_external_id: id, signature_status: 'sent' }
      fields[:status] = 'awaiting_signature' if contract.draft?
      contract.update!(fields)
    end
    delivery
  end

  def self.check_reference!(contract, id)
    return if contract.signature_external_id == id
    return if contract.signature_external_id.blank? && contract.signature_status != 'signed'

    raise JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_PROJECTION_CONFLICT'
  end
  private_class_method :check_reference!
end
