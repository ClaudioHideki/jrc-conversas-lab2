# Observed native workload, not a limit, admission receipt or transfer approval.
# Missing source visibility or explicit weights must never become spare capacity.
class JrcRelationship::PortfolioGroupWorkload
  MAX_ASSIGNMENTS = 10_000

  def initialize(context)
    @account_id = context.account.id
    @actor_id = context.user.id
  end

  def call(id)
    JrcRelationship::PortfolioGroup.transaction do
      JrcRelationship::BatchReviewAuthority.new(account_id: @account_id, actor_id: @actor_id, write: false).call do |context|
        projection(context, id)
      end
    end
  end

  private

  def projection(context, id)
    group = JrcRelationship::PortfolioGroupScope.resolve(context).find(id)
    links = group.customer_links.where(account_id: context.account.id, active: true)
    visible = context.assignments
    return unavailable('scope_denied') if links.where.not(assignment_id: visible.select(:id)).exists?

    records = visible.where(id: links.select(:assignment_id), status: JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES)
    count = records.count
    return unavailable('controlled_review_required') if count > MAX_ASSIGNMENTS

    { state: 'observed', read_only: true, load_statuses: JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES,
      measures: JrcRelationship::CapacityWorkload::UNITS.map { |unit| measure(records, unit, count) } }
  end

  def unavailable(state)
    { state: state, read_only: true, measures: [] }
  end

  def measure(records, unit, count)
    value = unit == 'customers' ? count : JrcRelationship::CapacityWorkload.sum(records, unit).to_f
    { unit: unit, state: 'available', value: value }
  rescue JrcRelationship::CapacityWorkload::Unavailable
    { unit: unit, state: 'explicit_inputs_missing', value: nil }
  end
end
