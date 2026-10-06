class JrcRelationship::Renewal < JrcRelationship::Record
  self.table_name = 'jrc_relationship_renewals'
  belongs_to :contract, class_name: 'JrcCrm::Contract'
  belongs_to :deal, class_name: 'JrcCrm::Deal', optional: true
  validates :renewal_on, presence: true
  validates :status, inclusion: { in: %w[open negotiating won lost] }
  validates :proposed_mrr_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
