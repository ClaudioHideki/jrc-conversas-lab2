# Uses the same observed factors, weights and thresholds as the native health
# calculation. Missing or blocked scores do not imply a healthy customer.
class JrcRelationship::HealthRecommendation
  def self.call(health:, rules:)
    threshold = rules.fetch('risk_threshold')
    reasons = health.fetch(:factors).select { |factor| factor[:available] && factor[:weight].positive? && factor[:normalized] < threshold }
    state = state_for(health, reasons)
    { health: health, evidence: reasons, recommendation_state: state, evidence_threshold: threshold,
      recommended_action: I18n.t("jrc_relationship.recommendations.#{state}"), external_actions_require_confirmation: true }
  end

  def self.state_for(health, reasons)
    return 'unavailable' if health.fetch(:score).nil?

    reasons.empty? ? 'maintain_cadence' : 'review_factors'
  end
  private_class_method :state_for
end
