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
end
