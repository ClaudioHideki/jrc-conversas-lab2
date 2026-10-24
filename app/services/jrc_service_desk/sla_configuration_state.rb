# frozen_string_literal: true

# A missing measurement is distinct from an explicitly non-applicable SLA.
module JrcServiceDesk::SlaConfigurationState
  def self.reason(snapshot, kinds)
    return 'targets_and_calendar_missing' unless snapshot

    budgets = snapshot.policy_conditions['clock_budgets_seconds']
    unless budgets.is_a?(Hash) && budgets.keys.sort == kinds.sort &&
           budgets.values.all? { |value| value.is_a?(Integer) && value.positive? && value <= ((2**53) - 1) }
      return 'targets_missing'
    end
    JrcServiceDesk::SnapshotCalendar.new(timezone: snapshot.timezone, conditions: snapshot.calendar_conditions)
    nil
  rescue JrcServiceDesk::LifecycleDependencyError
    'calendar_missing'
  end
end
