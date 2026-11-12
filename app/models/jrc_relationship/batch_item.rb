class JrcRelationship::BatchItem < ApplicationRecord
  self.table_name = 'jrc_relationship_batch_items'
  belongs_to :account
  belongs_to :batch_review, class_name: 'JrcRelationship::BatchReview', inverse_of: :items
  belongs_to :assignment, class_name: 'JrcRelationship::Assignment', optional: true
  belongs_to :company, class_name: 'JrcCustomers::Company', optional: true
  validate :native_subject
  validates :state, inclusion: { in: %w[pending applied failed canceled] }
  validates :ordinal, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 50 }

  private

  def native_subject
    if company_id
      errors.add(:company, 'must be the same-account subject of a native master review') unless master_subject?
    elsif assignment_id.nil?
      errors.add(:assignment, 'is required for the original reviewed operations')
    end
  end

  def master_subject?
    batch_review&.inputs&.fetch('operation', nil) == 'master_allocation' && company&.account_id == account_id
  end
end
