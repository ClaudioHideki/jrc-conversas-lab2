# frozen_string_literal: true

# Pure arithmetic over the actual grouped SQL result, shared with isolated tests.
# Missing data is not mapped to zero by the transport; a successful empty query is.
class JrcServiceDesk::KpiCounts
  PHASES = %w[open waiting resolved closed cancelled].freeze
  def self.call(groups)
    phases = PHASES.to_h { |phase| [phase, 0] }
    statuses = groups.map do |key, count|
      id, name, phase = key
      raise ArgumentError, 'Unexpected phase/count' unless phases.key?(phase) && count.is_a?(Integer) && count >= 0
      phases[phase] += count
      { id: id.to_s, name: name, phase: phase, count: count }
    end
    { total: phases.values.sum, phases: phases, active: phases['open'] + phases['waiting'],
      by_status: statuses.sort_by { |row| [-row[:count], row[:id].to_i] } }
  end
end
