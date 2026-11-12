# The immutable outcome is already committed before this operational view is
# updated. A projection conflict cannot erase an acknowledged external send.
class JrcBackoffice::Signatures::DeliveryProjection
  STATES = { 'sent' => 'sent', 'completion_reported' => 'sent', 'canceled' => 'canceled', 'declined' => 'failed' }.freeze

  def self.call(delivery)
    id = delivery.external_id
    return delivery unless id

    contract = delivery.contract
    contract.with_lock('FOR NO KEY UPDATE') do
      delivery.with_lock('FOR NO KEY UPDATE') { project!(delivery, contract, id) }
    end
    delivery
  end

  def self.project!(delivery, contract, id)
    # Read the current fact only after both locks. A delayed "sent" worker
    # cannot overwrite a cancellation already committed/projected by another.
    state = STATES[delivery.state]
    return unless state

    current = current_delivery(contract)
    return if historical?(delivery, current)

    check_reference!(contract, delivery, id, current)
    return if contract.signature_status == 'signed'

    fields = { signature_mode: 'provider', signature_provider: delivery.snapshot.fetch('provider'),
               signature_external_id: id, signature_status: state }
    fields[:status] = 'awaiting_signature' if state == 'sent' && contract.draft?
    contract.update!(fields)
  end

  def self.check_reference!(contract, delivery, id, current)
    return if contract.signature_external_id == id
    return if contract.signature_external_id.blank? && contract.signature_status != 'signed'
    return if may_advance?(contract, delivery, current)

    raise JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_PROJECTION_CONFLICT'
  end

  def self.historical?(delivery, current)
    current && finished?(delivery) && newer?(current, delivery)
  end

  def self.may_advance?(contract, delivery, current)
    return false if contract.signature_status == 'signed'

    current && finished?(current) && newer?(delivery, current) && latest?(delivery)
  end

  def self.current_delivery(contract)
    return if contract.signature_external_id.blank?

    rows = JrcBackoffice::SignatureDelivery.joins(:events, :connection).where(account_id: contract.account_id, contract_id: contract.id)
                                           .where(jrc_backoffice_signature_delivery_events: { external_id: contract.signature_external_id })
                                           .where(jrc_backoffice_signature_connections: { provider: contract.signature_provider }).limit(2).to_a
    rows.first if rows.length == 1
  end

  def self.finished?(delivery)
    delivery.state.in?(%w[canceled declined])
  end

  def self.newer?(candidate, previous)
    candidate.id > previous.id && candidate.contract_version.number > previous.contract_version.number
  end

  def self.latest?(delivery)
    JrcBackoffice::SignatureDelivery.where(account_id: delivery.account_id,
                                           contract_id: delivery.contract_id).order(id: :desc).pick(:id) == delivery.id
  end
  private_class_method :project!, :check_reference!, :current_delivery, :finished?, :newer?, :latest?, :historical?, :may_advance?
end
