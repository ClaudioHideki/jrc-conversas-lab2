# frozen_string_literal: true

# Recovery-style polling of durable native clocks; the approved JSON policy is
# the intent. Default/legacy/manual policies produce neither jobs nor mutations.
class JrcServiceDesk::ClockMonitoringJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    automatic_sla_clocks.find_each(batch_size: 100) { |clock| monitor(clock) }
    automatic_ola_clocks.find_each(batch_size: 100) { |clock| monitor(clock) }
  end

  private

  def automatic_sla_clocks
    JrcServiceDesk::SlaClock.joins(sla_cycle: :lifecycle_policy_version)
      .where(state: %w[running paused completed])
      .where('jrc_service_desk_lifecycle_policy_versions.definition @> ?::jsonb',
             { sla: { escalation_policy: { automatic: true } } }.to_json)
  end

  def automatic_ola_clocks
    JrcServiceDesk::OlaClock.where(state: %w[running paused completed])
      .where('escalation_snapshot @> ?::jsonb', { automatic: true }.to_json)
  end

  def monitor(clock)
    binding = JrcServiceDesk::ClockMonitoringBinding.new(clock)
    return unless binding.automatic?

    member = JrcServiceDesk::ClockAutomationAuthority.verify!(binding.policy, account: clock.account, unit: clock.unit)
    context = { account: clock.account, user: member.user, account_user: member }
    JrcServiceDesk::EvaluateClocksService.new(user_context: context).evaluate_clock(
      kind: binding.kind, clock_id: clock.id, policy_digest: binding.digest
    )
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, JrcServiceDesk::IdempotencyConflict,
         JrcServiceDesk::LifecycleDependencyError, ActiveRecord::RecordInvalid, ArgumentError, KeyError
    # Revocation/missing dependency is a closed outcome. Avoid raw exception,
    # policy content, customer identity or secrets in the scheduler log.
    nil
  end
end
