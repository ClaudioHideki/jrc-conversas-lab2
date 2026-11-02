# Formalization shares the existing approval engine; it has no local votes or policy rules.
class JrcBackoffice::ContractRelease
  def self.check!(order:, actor:)
    JrcApprovals::CommercialGate.check!(resource: order, user: actor, key: 'crm.order_price')
    order.backoffice_requests.where(request_kind: 'fulfillment').order(:id).each do |request|
      if request.workflow_version == 2 && request.stage_applicable?('approval') &&
         JrcApprovals::CommercialGate.mode(order.account, 'backoffice.release') != 'enforcement'
        raise JrcApprovals::Error, 'POLICY_REQUIRED'
      end
      JrcApprovals::CommercialGate.check!(resource: request, user: actor, key: 'backoffice.release')
    end
  end
end
