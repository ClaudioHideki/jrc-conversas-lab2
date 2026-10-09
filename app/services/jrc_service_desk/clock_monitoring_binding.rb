# frozen_string_literal: true

# Exact historical clock plus currently approved policy. It never authorizes a
# second clock on the same ticket under another manual policy or another actor.
class JrcServiceDesk::ClockMonitoringBinding
  attr_reader :clock, :policy, :digest, :kind

  def initialize(clock)
    @clock = clock
    @kind = clock.is_a?(JrcServiceDesk::SlaClock) ? 'sla' : 'ola'
    kind == 'sla' ? bind_sla! : bind_ola!
  end

  def automatic?
    policy.automatic? && %w[running paused completed].include?(clock.state)
  end

  def verify!(expected_digest:, execution_account_user_id:)
    raise JrcServiceDesk::IdempotencyConflict, 'Clock monitoring publication changed' unless automatic? && digest == expected_digest
    raise Pundit::NotAuthorizedError unless policy.execution_account_user_id == execution_account_user_id

    JrcServiceDesk::ClockAutomationAuthority.verify!(policy, account: clock.account, unit: clock.unit)
  end

  private

  def bind_sla!
    cycle = clock.sla_cycle
    version = cycle.lifecycle_policy_version
    current = JrcServiceDesk::LifecycleSelector.new(clock.ticket).applicable
    valid = current&.id == version.id && version.lifecycle_policy.current_version_id == version.id &&
            version.digest == version.expected_digest && clock.ticket.lifecycle_policy_version_id == version.id
    raise JrcServiceDesk::IdempotencyConflict, 'Historical SLA monitoring publication is not current' unless valid

    @policy = JrcServiceDesk::ClockEscalationPolicy.new(version.definition.dig('sla', 'escalation_policy') || {})
    @digest = version.digest
  end

  def bind_ola!
    queue = clock.queue.reload
    current_policy = JrcServiceDesk::ClockEscalationPolicy.new(queue.ola_escalation_policy)
    revision = JrcServiceDesk::OlaTracker.current_revision(queue, clock.sla_snapshot)
    valid = queue.active? && queue.id == clock.ticket.queue_id && queue.unit_id == clock.unit_id &&
            queue.account_id == clock.account_id && revision == clock.policy_revision &&
            current_policy.definition == clock.escalation_snapshot
    raise JrcServiceDesk::IdempotencyConflict, 'Historical OLA monitoring publication is not current' unless valid

    @policy = JrcServiceDesk::ClockEscalationPolicy.new(clock.escalation_snapshot)
    @digest = clock.policy_revision
  end
end
