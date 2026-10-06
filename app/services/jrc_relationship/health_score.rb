# Pure, explainable calculation. Unavailable factors carry no invented score.
class JrcRelationship::HealthScore
  def self.band(score, rules: {})
    return 'unavailable' if score.nil?
    return 'healthy' if score >= rules.fetch('healthy_threshold', 80)
    return 'attention' if score >= rules.fetch('risk_threshold', 60)
    return 'risk' if score >= rules.fetch('critical_threshold', 40)
    'critical'
  end

  def self.call(observations:, weights:, rules: {})
    available = observations.select { |_key, value| !value[:normalized].nil? }
    denominator = available.sum { |key, _value| weights.fetch(key).to_f }
    factors = observations.map do |key, value|
      weight = weights.fetch(key).to_f
      contribution = denominator.positive? && !value[:normalized].nil? ? value[:normalized].clamp(0, 100) * weight / denominator : nil
      { factor: key, raw: value[:raw], normalized: value[:normalized], weight: weight,
        contribution: contribution&.round(4), evidence: value[:evidence], available: !value[:normalized].nil? }
    end
    score = denominator.positive? ? factors.sum { |f| f[:contribution].to_f }.round(2).clamp(0, 100) : nil
    { score: score, band: band(score, rules: rules), factors: factors, coverage_weight: denominator }
  end
end
