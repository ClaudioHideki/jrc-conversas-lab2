# One current, authorized native contract proves a renewal. Multiple successors
# require an explicit selection; neither ID ordering nor a won deal is evidence.
class JrcRelationship::RenewalOutcome
  def initialize(context, renewal)
    @context = context
    @renewal = context.records(JrcRelationship::Renewal).find(renewal.id)
    @customer = @renewal.assignment.customer_context(context.member)
    @customer.contracts.find(@renewal.contract_id)
  end

  def candidates
    rows = @customer.contracts.where(source_contract_id: @renewal.contract_id, signature_status: 'signed', status: %w[active expiring])
    return rows unless @renewal.deal_id

    @customer.deals.find(@renewal.deal_id)
    rows.where(deal_id: @renewal.deal_id)
  end

  def resolve(selected_id: nil, lock: false)
    scope = lock ? candidates.lock : candidates
    choice = selected_id.presence || @renewal.metadata['renewed_contract_id'].presence
    return scope.find(choice) if choice

    rows = scope.limit(2).to_a
    rows.one? ? rows.fetch(0) : nil
  end

  def proof(contract)
    { 'renewed_contract_id' => contract.id, 'renewal_order_id' => contract.sales_order_id,
      'renewal_deal_id' => contract.deal_id, 'source_contract_id' => contract.source_contract_id,
      'signature_status' => contract.signature_status, 'signed_at' => contract.signed_at&.iso8601,
      'reconciled_at' => Time.current.iso8601 }
  end

  def self.cohort(context, renewals)
    groups = renewals.map { |row| cohort_row(context, row) }.group_by { |row| row[:source_id] }
    accepted = groups.filter_map { |_source, rows| agreed_proof(rows) }
    ambiguous = groups.count { |_id, rows| ambiguous?(rows) }
    { source_count: groups.size, renewed_count: accepted.size, ambiguous_source_count: ambiguous,
      contracts: context.account.jrc_crm_contracts.where(id: accepted.map(&:id)), missing_source_count: groups.size - accepted.size }
  end

  def self.cohort_row(context, row)
    outcome = new(context, row)
    { source_id: row.contract_id, selected: outcome.resolve, ambiguous: outcome.candidates.limit(2).count > 1 }
  end

  def self.agreed_proof(rows)
    proofs = rows.filter_map { |row| row[:selected] }.uniq(&:id)
    return unless proofs.one?

    proof = proofs.fetch(0)
    proof if rows.all? { |row| row[:selected]&.id == proof.id }
  end

  def self.ambiguous?(rows)
    rows.any? { |row| row[:ambiguous] && !row[:selected] } || rows.filter_map { |row| row[:selected]&.id }.uniq.size > 1
  end
  private_class_method :cohort_row, :agreed_proof, :ambiguous?
end
