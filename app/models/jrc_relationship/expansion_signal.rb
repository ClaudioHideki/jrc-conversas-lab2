class JrcRelationship::ExpansionSignal < JrcRelationship::Record
  self.table_name = 'jrc_relationship_expansion_signals'
  belongs_to :product, class_name: 'JrcCrm::Product', optional: true
  belongs_to :deal, class_name: 'JrcCrm::Deal', optional: true
  belongs_to :source_contract, class_name: 'JrcCrm::Contract', optional: true
  belongs_to :source_product, class_name: 'JrcCrm::Product', optional: true
  validates :title, presence: true
  validates :status, inclusion: { in: %w[suggested approved rejected converted] }
  validates :potential_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :deal, presence: true, if: -> { %w[approved converted].include?(status) }
  validate do
    previous = Array((metadata_in_database || {})['commercial_returns'])
    current = Array(metadata['commercial_returns'])
    errors.add(:metadata, 'recorded commercial returns are immutable') unless (previous - current).empty?
  end
end
