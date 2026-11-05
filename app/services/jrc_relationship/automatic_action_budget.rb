# An optional account-wide daily ceiling for monitoring-created CS actions.
# Existing actions and risk evidence remain visible and continue to be updated.
class JrcRelationship::AutomaticActionBudget
  def initialize(context:, assignment:)
    @context = context
    @assignment = assignment
  end

  def call
    @context = JrcRelationship::Context.new(@context.member)
    raise Pundit::NotAuthorizedError unless @context.user.active_for_authentication?

    @context.assignment(@assignment.id, write: true)
    JrcRelationship::Action.transaction do
      configuration = configuration_under_lock
      limit = configuration ? configuration.effective_rules.fetch('automatic_action_daily_limit') : 0
      next yield if limit.zero?

      day = account_day
      if automatic_actions.where(created_at: day...day.advance(days: 1)).limit(limit).count >= limit
        audit_suppression!(configuration, day)
        next nil
      end
      yield
    end
  end

  private

  def account_day
    zone = Time.find_zone(@context.account.reporting_timezone) || Time.zone
    Time.current.in_time_zone(zone).beginning_of_day
  end

  def configuration_under_lock
    connection = ApplicationRecord.connection
    key = connection.quote("relationship-automatic-action-budget:#{@context.account.id}")
    connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{key}, 0))")
    JrcRelationship::Configuration.where(account: @context.account, scope_key: 'account').lock('FOR SHARE').first
  end

  def automatic_actions
    JrcRelationship::Action.where(account: @context.account).where("metadata ->> 'automatic' = 'true'")
  end

  def audit_suppression!(configuration, day)
    key = "daily-budget:#{configuration.id}:#{configuration.version}:#{day.iso8601}"
    events = JrcCrm::AuditEvent.where(account: @context.account, resource_type: @assignment.class.name, resource_id: @assignment.id,
                                      event_type: 'relationship_updated').where("to_value ->> 'suppression_key' = ?", key)
    return if events.exists?

    @context.audit!(@assignment, action: 'automatic_action_suppressed', after: {
                      suppression_key: key, reason: 'account_daily_budget', next_allowed_at: day.advance(days: 1).iso8601
                    })
  end
end
