class JrcRelationship::CustomerDocument < ApplicationRecord
  self.table_name = 'jrc_relationship_customer_documents'
  CATEGORIES = %w[registration contract evidence other].freeze
  belongs_to :account
  belongs_to :responsible, class_name: 'User', optional: true
  belongs_to :assignment, class_name: 'JrcRelationship::Assignment'
  has_many :versions, class_name: 'JrcRelationship::DocumentVersion', foreign_key: :document_id,
                      inverse_of: :document, dependent: :restrict_with_exception
  validates :title, presence: true, length: { maximum: 160 }
  validates :category, inclusion: { in: CATEGORIES }
  validates :confidentiality, inclusion: { in: %w[operational restricted] }, allow_nil: true
  validates :requirement_key, format: { with: /\A[a-z][a-z0-9_-]{0,59}\z/ }, allow_nil: true
  validates :status, inclusion: { in: %w[active archived] }
  validate :responsible_belongs_to_account
  validate { errors.add(:assignment, 'must belong to the account') if assignment && assignment.account_id != account_id }
  private

  def responsible_belongs_to_account
    return unless will_save_change_to_responsible_id? && responsible_id

    errors.add(:responsible, 'must belong to the account') unless account.users.exists?(id: responsible_id)
  end
end
