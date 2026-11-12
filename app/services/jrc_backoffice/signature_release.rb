# Business release uses verified internal evidence, never a provider's raw state.
class JrcBackoffice::SignatureRelease
  MESSAGE = 'O contrato precisa estar assinado para liberar a implantação.'.freeze

  def self.operational_v2?(contract)
    contract.sales_order.backoffice_requests.exists?(account_id: contract.account_id, request_kind: 'fulfillment', workflow_version: 2)
  end

  def self.verified?(contract)
    contract && contract.signature_status == 'signed' && JrcApprovals::SignatureEvidence.call(contract)['state'] == 'verified'
  end

  def self.satisfied?(request)
    return false unless request.contract&.signature_status == 'signed'
    return true unless request.workflow_version == 2

    verified?(request.contract)
  end

  def self.order_satisfied?(order)
    return false if JrcCrm::OrderContractService.new(order: order).required? && !order.contracts.exists?(signature_status: 'signed')

    order.backoffice_requests.where(account_id: order.account_id, request_kind: 'fulfillment', workflow_version: 2).all? do |request|
      !request.stage_applicable?('contract') || satisfied?(request)
    end
  end
end
