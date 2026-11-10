class JrcRelationship::SentimentEvidenceProjection
  def self.annotate(signals:, configuration:)
    evidence = JrcRelationship::HealthFactorEvidenceProjection.call(signals: signals, configuration: configuration,
                                                                    factor: 'sentiment', window_rule: 'sentiment_window_days')
    return signals unless evidence

    signals.merge(sentiment_evidence: evidence, health: signals.fetch(:health).merge(sentiment_evidence_freshness: evidence))
  end
end
