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
    policy = rules.fetch('missing_factor_policy', 'renormalize')
    raise ArgumentError, 'Invalid missing factor policy' unless %w[renormalize neutral block].include?(policy)

    missing = observations.any? { |key, value| value[:normalized].nil? && weights.fetch(key).positive? }
    blocked = policy == 'block' && missing
    observations = apply_missing_policy(observations, policy)
    denominator = available_weight(observations, weights)
    factors = observations.map { |key, value| factor(key, value, weights.fetch(key).to_f, denominator) }
    score = score_for(factors, denominator, blocked)
    { score: score, band: band(score, rules: rules), factors: factors, coverage_weight: denominator,
      missing_factor_policy: policy, blocked: blocked }
  end

  def self.apply_missing_policy(observations, policy)
    observations.transform_values do |value|
      policy == 'neutral' && value[:normalized].nil? ? value.merge(normalized: 50, imputed: true) : value
    end
  end

  def self.available_weight(observations, weights)
    observations.reject { |_key, value| value[:normalized].nil? }.sum { |key, _value| weights.fetch(key).to_f }
  end

  def self.factor(key, value, weight, denominator)
    contribution = value[:normalized].clamp(0, 100) * weight / denominator if denominator.positive? && !value[:normalized].nil?
    { factor: key, raw: value[:raw], normalized: value[:normalized], weight: weight,
      contribution: contribution&.round(4), evidence: value[:evidence], available: !value[:normalized].nil? && !value[:imputed],
      imputed: value[:imputed] == true }
  end

  def self.score_for(factors, denominator, blocked)
    !blocked && denominator.positive? ? factors.sum { |factor| factor[:contribution].to_f }.round(2).clamp(0, 100) : nil
  end

  private_class_method :apply_missing_policy, :available_weight, :factor, :score_for
end
