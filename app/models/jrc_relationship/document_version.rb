class JrcRelationship::DocumentVersion < ApplicationRecord
  self.table_name = 'jrc_relationship_document_versions'
  belongs_to :account
  belongs_to :document, class_name: 'JrcRelationship::CustomerDocument'
  belongs_to :uploaded_by, class_name: 'User'
  has_one_attached :file
  attr_readonly :account_id, :document_id, :uploaded_by_id, :number, :valid_until, :change_reason
  validates :number, numericality: { only_integer: true, greater_than: 0 }
  validates :change_reason, presence: true, length: { maximum: 500 }
  validate do
    errors.add(:document, 'must belong to the account') if document && document.account_id != account_id
    errors.add(:uploaded_by, 'must belong to the account') unless AccountUser.exists?(account_id: account_id, user_id: uploaded_by_id)
  end
end
