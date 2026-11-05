# Optional priority inputs use native observed score movement and current SLA
# breach evidence. Zero weights leave the legacy priority factors unchanged.
class JrcRelationship::PrioritySignals
  RULES = %w[priority_trend priority_sla].freeze

  def self.validation_errors(rules)
    RULES.filter_map do |key|
      value = rules.fetch(key, 0)
      "#{key} must be a finite nonnegative weight" unless value.is_a?(Numeric) && value.finite? && value >= 0
    end
  end

  def self.call(data, rules)
    trend = data.dig(:health_change, :drop)
    breached = data[:sla_breached]
    {
      'trend' => { normalized: trend&.clamp(0, 100), raw_drop_points: trend,
                   source_snapshot_id: data.dig(:health_change, :snapshot_id), evidence: 'Authorized native HealthSnapshot score movement' },
      'sla' => { normalized: if breached.nil?
                               nil
                             else
                               (breached.positive? ? 100 : 0)
                             end, breached_count: breached,
                 evidence: 'Authorized current Service Desk SLA breaches; binary urgency evidence' }
    }.select { |key, _value| rules.fetch("priority_#{key}", 0).positive? }
  end
end
