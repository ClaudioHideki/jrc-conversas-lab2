# Deferral is not an execution receipt. Pending steps and immutable definitions
# stay in their native tables; the audit records only the actual blocked attempt.
class JrcRelationship::CadenceActionBudget
  def initialize(context, enrollment, step)
    @context = context
    @enrollment = enrollment
    @step = step
  end

  def call(&)
    return yield unless @step.definition.fetch('kind') == 'action'

    assignment = @context.assignment(@enrollment.assignment_id, write: true)
    budget = JrcRelationship::AutomaticActionBudget.new(context: @context, assignment: assignment)
    receipt = budget.call(&)
    defer!(budget.next_allowed_at) if budget.next_allowed_at
    receipt
  end

  def self.retry_at(enrollment)
    return unless enrollment.state == 'active'

    event = JrcCrm::AuditEvent.where(account_id: enrollment.account_id, resource_type: enrollment.class.name, resource_id: enrollment.id,
                                     event_type: 'relationship_updated')
                              .where("metadata ->> 'action' = 'cadence_budget_deferred'")
                              .where("to_value ->> 'revision' = ?", enrollment.revision.to_s).order(id: :desc).first
    event&.to_value&.fetch('next_allowed_at', nil)
  end

  private

  def defer!(until_at)
    return if self.class.retry_at(@enrollment) == until_at.iso8601(6)

    @context.audit!(@enrollment, action: 'cadence_budget_deferred', after: {
                      revision: @enrollment.revision, step_id: @step.id, reason: 'account_daily_budget', next_allowed_at: until_at.iso8601(6)
                    })
  end
end
