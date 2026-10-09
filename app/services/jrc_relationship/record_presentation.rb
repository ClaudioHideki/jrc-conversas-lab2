class JrcRelationship::RecordPresentation
  def self.adjustment_percent(record, contract)
    return unless contract.monthly_cents.positive? && record.proposed_mrr_cents

    (100.0 * (record.proposed_mrr_cents - contract.monthly_cents) / contract.monthly_cents).round(2)
  end

  def initialize(context, snapshot:, risk_actions:, risks: {})
    @context = context
    @snapshot = snapshot
    @risk_actions = risk_actions
    @risks = risks
  end

  def augment!(attrs, record)
    case record
    when JrcRelationship::RiskCase then risk!(attrs, record)
    when JrcRelationship::ExpansionSignal then expansion!(attrs, record)
    when JrcRelationship::Survey then survey!(attrs, record)
    when JrcRelationship::Renewal then renewal!(attrs, record)
    end
  end

  def customer_name(record)
    record.assignment&.label || record.try(:company)&.name || record.try(:contact)&.name
  end

  def self.customer_route(record)
    if record.company_id
      { name: 'jrc_customer_company', params: { companyId: record.company_id } }
    else
      { name: 'contacts_edit', params: { contactId: record.contact_id } }
    end
  end

  private

  def renewal!(attrs, record)
    customer = record.assignment.customer_context(@context.member)
    contract = customer.contracts.find(record.contract_id)
    attrs['commercial_context'] =
      renewal_context(record, contract).merge(renewal_signals(record, contract)).merge(renewal_documents(record, customer))
  end

  def renewal_context(record, contract)
    { contract_number: contract.contract_number, current_mrr_cents: contract.monthly_cents,
      successor_contracts: successor_contracts(record), contract_id: contract.id, ends_on: contract.ends_on,
      days_remaining: contract.ends_on && (contract.ends_on - Date.current).to_i }
  end

  def renewal_signals(record, contract)
    { health: @snapshot.call(record.assignment_id)&.signals&.dig('health')&.slice('score', 'band'),
      risks: @risks.fetch(record.assignment_id, []), adjustment_percent: self.class.adjustment_percent(record, contract),
      products: JrcCrm::OrderItem.where(sales_order_id: contract.sales_order_id).pluck(:name) }
  end

  def successor_contracts(record)
    JrcRelationship::RenewalOutcome.new(@context, record).candidates.map do |candidate|
      { id: candidate.id, number: candidate.contract_number, order_id: candidate.sales_order_id,
        deal_id: candidate.deal_id, signed_at: candidate.signed_at }
    end
  end

  def renewal_documents(record, customer)
    return { proposal_ids: [], order_ids: [] } unless record.deal_id

    proposals = customer.proposals.where(deal_id: record.deal_id)
    { proposal_ids: proposals.pluck(:id), order_ids: customer.orders.where(proposal_id: proposals.select(:id)).pluck(:id) }
  end

  def risk!(attrs, record)
    risk_financial!(attrs, record)
    attrs['health'] = @snapshot.call(record.assignment_id)&.signals&.dig('health')&.slice('score', 'band')
    attrs['origin'] = record.source_key.to_s.start_with?('manual:') ? 'manual' : record.kind
    action = @risk_actions[record.id.to_s]
    attrs['sla'] = JrcOperations::SlaClock.new(action).snapshot if action
  end

  def risk_financial!(attrs, record)
    if JrcRelationship::RiskFinancialSnapshot.visible?(record, @context)
      attrs['mrr_cents'] = record.financial_captured_at ? record.mrr_at_risk_cents : @snapshot.call(record.assignment_id)&.signals&.dig('mrr_cents')
    else
      attrs['mrr_cents'] = nil
      attrs['mrr_at_risk_cents'] = nil
      attrs['financial_snapshot'] = { 'available' => false, 'reason' => 'access_denied' }
    end
  end

  def expansion!(attrs, record)
    customer = record.assignment.customer_context(@context.member)
    deal = record.deal_id && customer.deals.find(record.deal_id)
    attrs['commercial_context'] = { product_name: record.product&.name,
                                    expansion_kind: record.metadata['expansion_kind'] || record.metadata['kind'] || 'upsell',
                                    origin: expansion_origin(record),
                                    commercial_returns: Array(record.metadata['commercial_returns']),
                                    deal: deal && { id: deal.id, title: deal.title, status: deal.status, value_cents: deal.value_cents },
                                    won_cents: won_cents(deal) }
  end

  def expansion_origin(record)
    record.metadata['automatic'] ? 'automatic' : 'manual'
  end

  def won_cents(deal)
    deal&.status == 'won' ? deal.value_cents : 0
  end

  def survey!(attrs, record)
    attrs['delivery_status'] = if record.responded_at
                                 'responded'
                               else
                                 record.expires_at <= Time.current ? 'expired' : record.status
                               end
    attrs['channel'] = record.metadata['sent_channel'] || 'public_link'
    attrs['source_links'] = JrcRelationship::SurveyLinks.new(@context, record).call
  end
end
