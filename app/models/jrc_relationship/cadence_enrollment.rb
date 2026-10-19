class JrcRelationship::CadenceEnrollment < ApplicationRecord
  self.table_name = 'jrc_relationship_cadence_enrollments'
  belongs_to :account
  belongs_to :assignment, class_name: 'JrcRelationship::Assignment'
  belongs_to :batch_review, class_name: 'JrcRelationship::BatchReview'
  has_many :steps, class_name: 'JrcRelationship::CadenceStep', dependent: :restrict_with_error
  validates :state, inclusion: { in: %w[active completed stopped] }
  after_create_commit { JrcRelationship::CadenceExecutionJob.perform_later(id) }
end
