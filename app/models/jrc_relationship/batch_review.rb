class JrcRelationship::BatchReview < ApplicationRecord
  self.table_name = 'jrc_relationship_batch_reviews'
  belongs_to :account
  belongs_to :actor, class_name: 'User', optional: true
  has_many :items, class_name: 'JrcRelationship::BatchItem', inverse_of: :batch_review, dependent: :restrict_with_error
  validates :request_id, :digest, :snapshot, :inputs, :expires_at, presence: true
  validates :state, inclusion: { in: %w[previewed running completed canceled attention] }
end
