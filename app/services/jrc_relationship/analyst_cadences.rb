# Operational source inventory only. Original playbook contents, conversation
# evidence and applied receipts are not disclosed by this supervisor listing.
class JrcRelationship::AnalystCadences
  # A departing analyst can own either execution authority or the active
  # customer portfolio. Callers still enforce current native assignment scope.
  def self.responsibilities(account, analyst)
    owned = JrcRelationship::Assignment.where(account: account, owner: analyst,
                                              status: JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES)
    rows = JrcRelationship::CadenceEnrollment.where(account: account)
    rows.where(actor_id: analyst.id).or(rows.where(assignment_id: owned.select(:id)))
  end

  def initialize(context)
    @authority = JrcRelationship::BatchReviewAuthority.new(account_id: context.account.id, actor_id: context.user.id, write: false)
  end

  def call(analyst_id, page: 1)
    page = Integer(page.to_s, 10)
    raise ActionController::BadRequest, 'Invalid cadence page' unless page.positive?

    @authority.call do |context|
      analyst, rows = authorized_source(context, analyst_id)
      selected = rows.order(id: :desc).offset((page - 1) * 10).limit(10).to_a
      { analyst: { id: analyst.id, name: analyst.name }, payload: project(context, selected, analyst.id),
        meta: { page: page, per_page: 10, total: rows.count }, can_stop: context.policy.manage? }
    end
  end

  private

  def authorized_source(context, analyst_id)
    raise Pundit::NotAuthorizedError unless context.policy.team?

    analyst = context.account.users.find(analyst_id)
    rows = self.class.responsibilities(context.account, analyst).where(state: 'active')
    raise Pundit::NotAuthorizedError if rows.where.not(assignment_id: context.assignments.select(:id)).exists?

    [analyst, rows]
  end

  def project(context, rows, analyst_id)
    assignments = context.assignments.where(id: rows.map(&:assignment_id)).includes(:company, :contact).index_by(&:id)
    pending = pending_summaries(context, rows)
    rows.map { |record| project_row(record, assignments.fetch(record.assignment_id), pending.fetch(record.id, [record.id, 0, nil]), analyst_id) }
  end

  def pending_summaries(context, rows)
    JrcRelationship::CadenceStep.where(account: context.account, cadence_enrollment_id: rows.map(&:id), state: 'pending')
                                .group(:cadence_enrollment_id).pluck(:cadence_enrollment_id, Arel.sql('COUNT(*)'), Arel.sql('MIN(due_at)'))
                                .index_by(&:first)
  end

  def project_row(record, assignment, pending, analyst_id)
    { id: record.id, revision: record.revision, assignment_id: assignment.id, customer_name: assignment.label,
      customer_360: JrcRelationship::RecordPresentation.customer_route(assignment), pending_steps: pending[1],
      next_due_at: pending[2]&.utc&.iso8601(6), responsibility: record.actor_id == analyst_id ? 'execution_actor' : 'portfolio_owner' }
  end
end
