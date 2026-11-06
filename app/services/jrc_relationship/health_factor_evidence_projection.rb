# Read-time validity of a captured observation; never rewrites its score/date.
class JrcRelationship::HealthFactorEvidenceProjection
  def self.call(signals:, configuration:, factor:, window_rule:, now: Time.current)
    captured = Array(signals.dig(:health, :factors)).find { |row| row[:factor] == factor }&.dig(:measurement)
    return unless captured

    current_days = configuration.effective_rules.fetch(window_rule)
    state = state(captured, current_days, now)
    captured.merge(state: state, captured_state: captured[:state], current_window_days: current_days,
                   recalculation_required: state != captured[:state] || state == 'stale')
  end

  def self.state(captured, current_days, now)
    return 'requires_refresh' unless captured[:window_days] == current_days
    return captured[:state] unless captured[:observed_at]

    observed = Time.iso8601(captured[:observed_at])
    return 'unavailable' if observed > now
    return 'stale' if observed < now - current_days.days

    captured[:state]
  rescue ArgumentError, TypeError
    'unavailable'
  end
  private_class_method :state
end
