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
    { id: @clock.id.to_s, kind: kind, state: @clock.state, budget_seconds: budget,
      elapsed_seconds: elapsed, remaining_seconds: [budget - elapsed, 0].max,
      consumed_percent: elapsed * 100.0 / budget, breached: elapsed > budget,
      due_at: @clock.due_at.iso8601(6), observed_at: @now.iso8601(6),
      achieved_at: @clock.respond_to?(:achieved_at) ? @clock.achieved_at&.iso8601(6) : @clock.ended_at&.iso8601(6),
      timezone: snapshot&.timezone, time_basis: @clock.respond_to?(:time_basis) ? @clock.time_basis : 'business' }
  end

  private

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
