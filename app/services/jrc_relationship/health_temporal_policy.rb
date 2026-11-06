class JrcRelationship::HealthTemporalPolicy
  def self.validation_errors(rules)
    errors = %w[satisfaction_window_days health_trend_window_days sentiment_window_days].filter_map do |key|
      value = rules.fetch(key)
      "#{key} must be a whole number from 1 to 3650 days" unless value.is_a?(Integer) && value.between?(1, 3650)
    end
    hours = rules.fetch('automatic_action_cooldown_hours')
    errors << 'automatic action cooldown must be from 0 to 8760 hours' unless hours.is_a?(Numeric) && hours.finite? && hours.between?(0, 8760)
    errors
  end
end
