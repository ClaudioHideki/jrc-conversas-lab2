class JrcRelationship::BatchItem < ApplicationRecord
  self.table_name = 'jrc_relationship_batch_items'
  belongs_to :account
  belongs_to :batch_review, class_name: 'JrcRelationship::BatchReview', inverse_of: :items
  belongs_to :assignment, class_name: 'JrcRelationship::Assignment'
  validates :state, inclusion: { in: %w[pending applied failed canceled] }
  validates :ordinal, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 50 }
end
