class JrcRelationship::CustomerDocument < ApplicationRecord
  self.table_name = 'jrc_relationship_customer_documents'
  belongs_to :account
  belongs_to :assignment, class_name: 'JrcRelationship::Assignment'
  has_many :versions, class_name: 'JrcRelationship::DocumentVersion', foreign_key: :document_id,
                      inverse_of: :document, dependent: :restrict_with_exception
  validates :title, presence: true, length: { maximum: 160 }
  validates :category, inclusion: { in: %w[registration contract evidence other] }
  validates :status, inclusion: { in: %w[active archived] }
  validate { errors.add(:assignment, 'must belong to the account') if assignment && assignment.account_id != account_id }
end
