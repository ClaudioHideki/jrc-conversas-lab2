# frozen_string_literal: true

# Reading a clock does not persist elapsed time, violations, alerts or transitions.
class JrcServiceDesk::ClockProjection
  def initialize(clock, now: Time.current)
    @clock = clock
    @now = now
  end

  def call
    elapsed = current_elapsed
    budget = @clock.budget_seconds
    breached = elapsed > budget
    { id: @clock.id.to_s, kind: kind, state: @clock.state, deadline_state: deadline_state(elapsed, budget, breached), budget_seconds: budget,
      elapsed_seconds: elapsed, remaining_seconds: [budget - elapsed, 0].max,
      consumed_percent: elapsed * 100.0 / budget, breached: breached,
      due_at: @clock.due_at.iso8601(6), observed_at: @now.iso8601(6),
      achieved_at: @clock.respond_to?(:achieved_at) ? @clock.achieved_at&.iso8601(6) : @clock.ended_at&.iso8601(6),
      timezone: snapshot&.timezone, time_basis: @clock.respond_to?(:time_basis) ? @clock.time_basis : 'business' }
  end

  private

  def deadline_state(elapsed, budget, breached)
    return @clock.state unless @clock.state == 'running'
    return 'overdue' if breached

    settings = if @clock.respond_to?(:sla_cycle)
                 @clock.sla_cycle.lifecycle_policy_version.definition.dig('sla', 'escalation_policy') || {}
               else
                 @clock.escalation_snapshot
               end
    policy = JrcServiceDesk::ClockEscalationPolicy.new(settings)
    if policy.enabled? && policy.thresholds.any? { |row| row['percent'] < 100 && elapsed * 100.0 / budget >= row['percent'] }
      return 'near_due'
    end

    'on_time'
  end

  def kind
    @clock.respond_to?(:kind) ? @clock.kind : 'ola'
  end

  def snapshot
    @clock.respond_to?(:sla_cycle) ? @clock.sla_cycle.sla_snapshot : @clock.sla_snapshot
  end

  def current_elapsed
    elapsed = @clock.elapsed_seconds.to_f
    return elapsed unless @clock.state == 'running' && @now > @clock.anchor_at
    return elapsed + (@now - @clock.anchor_at) if @clock.respond_to?(:time_basis) && @clock.time_basis == 'calendar'

    calendar = JrcServiceDesk::SnapshotCalendar.new(timezone: snapshot.timezone, conditions: snapshot.calendar_conditions)
    elapsed + calendar.elapsed(@clock.anchor_at, @now)
  end
end
