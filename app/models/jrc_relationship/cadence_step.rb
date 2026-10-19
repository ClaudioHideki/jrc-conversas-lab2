class JrcRelationship::CadenceStep < ApplicationRecord
  self.table_name = 'jrc_relationship_cadence_steps'
  belongs_to :account
  belongs_to :cadence_enrollment, class_name: 'JrcRelationship::CadenceEnrollment'
  validates :state, inclusion: { in: %w[pending applied canceled] }
  validates :ordinal, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 50 }
end
