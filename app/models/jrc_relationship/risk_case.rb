class JrcRelationship::RiskCase < JrcRelationship::Record
  self.table_name = 'jrc_relationship_risk_cases'
  validates :reason, :source_key, presence: true
  validates :severity, inclusion: { in: %w[low medium high critical] }
  validates :status, inclusion: { in: %w[detected analyzing planned negotiating retained churn no_action] }
  validates :outcome, presence: true, if: -> { %w[retained churn no_action].include?(status) }
  validate { errors.add(:plan, 'must be structured retention data') unless plan.is_a?(Hash) }
end
