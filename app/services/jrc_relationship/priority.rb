# Pure priority calculation; factors and urgency floor travel with each action.
class JrcRelationship::Priority
  def self.call(data:, rules:, kind:, today: Date.today, manual_priority: nil)
    score = data.dig(:health, :score)
    days = data[:renewal_on] && (data[:renewal_on] - today).to_i
    raw = { 'health' => score && 100 - score, 'mrr' => data[:mrr_cents] && (data[:mrr_cents].to_f * 100 / rules.fetch('mrr_priority_ceiling_cents')).clamp(0, 100),
      'renewal' => days && (100 - days * 100.0 / rules.fetch('renewal_days')).clamp(0, 100),
      'inactivity' => data[:days_without_contact] && (data[:days_without_contact].to_f * 100 / rules.fetch('no_contact_days')).clamp(0, 100) }
    denominator = raw.sum { |key, value| value.nil? ? 0 : rules.fetch("priority_#{key}") }
    factors = raw.to_h do |key, value|
      weight = rules.fetch("priority_#{key}")
      contribution = value && denominator.positive? ? value.clamp(0, 100) * weight / denominator : nil
      [key, { normalized: value, weight: weight, contribution: contribution, available: !value.nil? }]
    end
    urgency = if score && score < rules.fetch('critical_threshold')
                rules.fetch('critical_action_priority')
              elsif kind == 'ticket' && (data[:critical_tickets].to_i.positive? || data[:sla_breached].to_i.positive?)
                rules.fetch('ticket_action_priority')
              elsif kind == 'satisfaction'
                rules.fetch('detractor_action_priority')
              elsif kind == 'health_drop'
                rules.fetch('health_drop_action_priority')
              else 0
              end
    weighted = factors.values.sum { |factor| factor[:contribution].to_f }
    calculated = [weighted, urgency].max.round.clamp(0, 100)
    { score: manual_priority.nil? ? calculated : manual_priority, factors: factors.merge('urgency_floor' => urgency) }
  end
end
