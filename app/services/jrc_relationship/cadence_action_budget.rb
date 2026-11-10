# Deferral is not an execution receipt. Pending steps and immutable definitions
# stay in their native tables; the audit records only the actual blocked attempt.
class JrcRelationship::CadenceActionBudget
  GOVERNED_KINDS = %w[action activity meeting].freeze
  AVAILABILITY_RETRY_SECONDS = 300

  def initialize(context, enrollment, step)
    @context = context
    @enrollment = enrollment
    @step = step
  end

  def call(&)
    return yield unless GOVERNED_KINDS.include?(@step.definition.fetch('kind'))

    assignment = @context.assignment(@enrollment.assignment_id, write: true)
    budget = JrcRelationship::AutomaticActionBudget.new(context: @context, assignment: assignment)
    receipt = JrcRelationship::Action.transaction(requires_new: true) { budget.call(&) }
    defer!(budget.next_allowed_at, 'account_daily_budget') if budget.next_allowed_at
    receipt
  rescue JrcRelationship::Workflow::AutomaticWorkUnavailable
    defer!(Time.current + AVAILABILITY_RETRY_SECONDS, 'native_assignment_unavailable')
    nil
  end

  def self.retry_at(enrollment)
    deferral(enrollment).fetch('retry_at')
  end

  def self.deferral(enrollment)
    empty = { 'retry_at' => nil, 'retry_reason' => nil }
    return empty unless enrollment.state == 'active'

    event = JrcCrm::AuditEvent.where(account_id: enrollment.account_id, resource_type: enrollment.class.name, resource_id: enrollment.id,
                                     event_type: 'relationship_updated')
                              .where("metadata ->> 'action' IN (?)", %w[cadence_budget_deferred cadence_assignment_deferred])
                              .where("to_value ->> 'revision' = ?", enrollment.revision.to_s).order(id: :desc).first
    event ? deferred_presentation(event) : empty
  end

  def self.deferred_presentation(event)
    data = event.to_value
    next_at = Time.iso8601(data.fetch('next_allowed_at'))
    if data.fetch('reason') == 'native_assignment_unavailable' && next_at <= Time.current
      interval = data.fetch('retry_interval_seconds')
      next_at += (((Time.current - next_at) / interval).floor + 1) * interval
    end
    { 'retry_at' => next_at.iso8601(6), 'retry_reason' => data.fetch('reason') }
  end
  private_class_method :deferred_presentation

  private

  def defer!(until_at, reason)
    current = self.class.deferral(@enrollment)
    return if current['retry_reason'] == reason && (reason == 'native_assignment_unavailable' || current['retry_at'] == until_at.iso8601(6))

    action = reason == 'account_daily_budget' ? 'cadence_budget_deferred' : 'cadence_assignment_deferred'
    details = { revision: @enrollment.revision, step_id: @step.id, reason: reason, next_allowed_at: until_at.iso8601(6) }
    details[:retry_interval_seconds] = AVAILABILITY_RETRY_SECONDS if reason == 'native_assignment_unavailable'
    @context.audit!(@enrollment, action: action, after: details)
  end
end
