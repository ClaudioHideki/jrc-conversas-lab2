# frozen_string_literal: true

# Calendar-aware confirmation of candidates; crossing an end-of-shift boundary
# alone does not consume extra business seconds. Uses the same engine as detail.
class JrcServiceDesk::ClockBreachQuery
  def self.count(clocks, now: Time.current)
    clocks.where(state: 'running').where('due_at < ?', now)
          .includes(sla_cycle: %i[sla_snapshot lifecycle_policy_version]).count do |clock|
      JrcServiceDesk::ClockProjection.new(clock, now: now).call[:breached]
    end
  end

  # The customer summary counts affected tickets, not individual clocks. A
  # paused clock only contributes an already-consumed breach, never idle time.
  def self.ticket_count(clocks, now: Time.current)
    running = clocks.where(state: 'running').where('due_at < ?', now)
    paused = clocks.where(state: 'paused').where('elapsed_seconds > budget_seconds')
    running.or(paused).includes(sla_cycle: %i[sla_snapshot lifecycle_policy_version]).filter_map do |clock|
      clock.ticket_id if JrcServiceDesk::ClockProjection.new(clock, now: now).call[:breached]
    end.uniq.length
  end
end
