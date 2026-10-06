class JrcRelationship::Survey < JrcRelationship::Record
  include JrcRelationship::SignalDispatch
  self.table_name = 'jrc_relationship_surveys'
  validates :kind, inclusion: { in: %w[nps ces] }
  validates :token_digest, :expires_at, presence: true
  validates :score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }, allow_nil: true
  validates :comment, length: { maximum: 4000 }
end
