# Read-time freshness is separate from the immutable score as calculated.
# Opening a cached snapshot never renews its observation date or score.
class JrcRelationship::SatisfactionEvidenceProjection
  def self.annotate(signals:, configuration:)
    evidence = call(signals: signals, configuration: configuration)
    return signals unless evidence

    signals.merge(satisfaction_evidence: evidence, health: signals.fetch(:health).merge(evidence_freshness: evidence))
  end

  def self.call(signals:, configuration:, now: Time.current)
    JrcRelationship::HealthFactorEvidenceProjection.call(signals: signals, configuration: configuration,
                                                         factor: 'satisfaction', window_rule: 'satisfaction_window_days', now: now)
  end
end
