class JrcRelationship::RiskCase < JrcRelationship::Record
  self.table_name = 'jrc_relationship_risk_cases'
  validates :reason, :source_key, presence: true
  validates :severity, inclusion: { in: %w[low medium high critical] }
  validates :status, inclusion: { in: %w[detected analyzing planned negotiating retained churn no_action] }
  validates :outcome, presence: true, if: -> { %w[retained churn no_action].include?(status) }
  validate { errors.add(:plan, 'must be structured retention data') unless plan.is_a?(Hash) }
  validates :mrr_at_risk_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate do
    if persisted? && changes.keys.intersect?(%w[mrr_at_risk_cents financial_snapshot financial_captured_at])
      errors.add(:base, 'the opening financial snapshot is immutable')
    end
  end
end
