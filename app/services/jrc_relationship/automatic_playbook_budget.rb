require 'digest'

# A denied admission is not an execution receipt. The native monitor reevaluates
# current causes and playbook versions; this does not schedule a guaranteed run.
class JrcRelationship::AutomaticPlaybookBudget
  GOVERNED_KINDS = %w[action activity meeting].freeze
  EVENT = 'automatic_playbook_budget_evaluated'.freeze

  def initialize(context, assignment)
    @context = context
    @assignment = assignment
  end

  def call(steps, &)
    return yield if steps.empty?

    @key = Digest::SHA256.hexdigest(steps.map { |key, step, _book| [key, step] }.to_json)
    keys = action_keys(steps)
    @required = keys.size - @assignment.actions.where(source_key: keys).count
    return yield if keys.empty?

    admit!(&)
  rescue JrcRelationship::Workflow::AutomaticWorkUnavailable
    record!('deferred', 'native_assignment_unavailable', Time.current + 300)
    nil
  end

  def last_attempt
    @context.assignment(@assignment.id)
    row = events.order(id: :desc).first
    return unless row

    row.to_value.slice('state', 'reason', 'required_actions', 'eligible_after').merge('attempted_at' => row.created_at)
  end

  private

  def action_keys(steps)
    steps.filter_map do |key, step, _book|
      next unless GOVERNED_KINDS.include?(step.fetch('kind'))

      step['kind'] == 'action' ? key : "activity:#{key}"
    end.uniq
  end

  def events
    JrcCrm::AuditEvent.where(account_id: @context.account.id, resource_type: @assignment.class.name, resource_id: @assignment.id,
                             event_type: 'relationship_updated').where("metadata ->> 'action' = ?", EVENT)
  end

  def admit!(&)
    budget = JrcRelationship::AutomaticActionBudget.new(context: @context, assignment: @assignment)
    result = JrcRelationship::Action.transaction(requires_new: true) do
      value = @required.positive? ? budget.call(required: @required, &) : yield
      record!('admitted', 'budget_available') unless budget.next_allowed_at
      value
    end
    record!('deferred', 'account_daily_budget', budget.next_allowed_at) if budget.next_allowed_at
    result
  end

  def record!(state, reason, eligible_after = nil)
    values = { 'source_digest' => @key, 'state' => state, 'reason' => reason,
               'required_actions' => @required, 'eligible_after' => eligible_after&.iso8601(6) }
    previous = events.where("to_value ->> 'source_digest' = ?", @key).order(id: :desc).first
    return if previous && (previous.to_value == values || availability_deferred?(previous.to_value, values))

    @context.audit!(@assignment, action: EVENT, after: values)
  end

  def availability_deferred?(previous, current)
    current['reason'] == 'native_assignment_unavailable' && previous['reason'] == current['reason'] &&
      previous['state'] == current['state'] && previous['eligible_after'] && Time.iso8601(previous['eligible_after']) > Time.current
  end
end
