class JrcRelationship::RenewalReconciliation
  def initialize(context, assignment)
    @context = context
    @assignment = assignment
  end

  def call
    @context.records(JrcRelationship::Renewal).where(assignment: @assignment, status: %w[open negotiating]).find_each do |row|
      reconcile!(row)
    end
  end

  private

  def reconcile!(row)
    row.with_lock do
      # Recheck under the native lock; a retry cannot overwrite a newer outcome.
      next unless %w[open negotiating].include?(row.status)

      fresh = JrcRelationship::Context.new(@context.member)
      outcome = JrcRelationship::RenewalOutcome.new(fresh, row)
      signed = outcome.resolve(lock: true)
      customer = row.assignment.customer_context(fresh.member)
      lost = row.deal_id && customer.deals.exists?(id: row.deal_id, status: 'lost')
      next unless signed || lost

      before = { status: row.status }
      proof = signed ? outcome.proof(signed) : { 'reconciled_at' => Time.current.iso8601 }
      row.update!(status: signed ? 'won' : 'lost', metadata: row.metadata.merge(proof))
      fresh.audit!(row, before: before, after: { status: row.status, native_proof: proof }, action: 'renewal_commercial_result')
    end
  end
end
