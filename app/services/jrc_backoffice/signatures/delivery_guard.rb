# The stored intent reserves this contract before any external I/O. Every
# legal-source writer must hold the native account/order/contract locks.
class JrcBackoffice::Signatures::DeliveryGuard
  def self.active(contract)
    finished = JrcBackoffice::SignatureDeliveryEvent.where(account_id: contract.account_id,
                                                           kind: JrcBackoffice::SignatureDeliveryEvent::TERMINAL).select(:delivery_id)
    JrcBackoffice::SignatureDelivery.where(account_id: contract.account_id, contract_id: contract.id).where.not(id: finished)
  end

  def self.check_editable!(contract)
    return unless active(contract).exists?

    raise JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_IN_PROGRESS'
  end
end
