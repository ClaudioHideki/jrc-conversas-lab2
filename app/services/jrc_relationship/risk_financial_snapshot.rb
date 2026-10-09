class JrcRelationship::RiskFinancialSnapshot
  def self.capture!(risk, context)
    return risk unless risk.new_record?

    customer = risk.assignment.customer_context(context.member)
    contracts = customer.contracts.where(status: %w[active expiring]).order(:id)
    available = JrcOperations::Access.crm?(context.member)
    amounts = available ? contracts.pluck(:id, :monthly_cents) : []
    risk.financial_captured_at = Time.current
    risk.mrr_at_risk_cents = amounts.sum(&:last) if available
    risk.financial_snapshot = { 'available' => available, 'reason' => available ? 'authorized_active_contracts' : 'crm_unavailable',
                                'contract_ids' => amounts.map(&:first), 'contract_monthly_cents' => amounts.to_h,
                                'actor_id' => context.user.id, 'captured_at' => risk.financial_captured_at.iso8601 }
    risk
  end

  def self.visible?(risk, context)
    return false unless JrcOperations::Access.crm?(context.member)
    return true unless risk.financial_captured_at

    ids = Array(risk.financial_snapshot['contract_ids'])
    risk.assignment.customer_context(context.member).contracts.where(id: ids).count == ids.size
  end
end
