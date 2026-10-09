class JrcRelationship::SurveyDispatchDecision < ApplicationRecord
  self.table_name = 'jrc_relationship_survey_dispatch_decisions'
  belongs_to :account
  belongs_to :survey, class_name: 'JrcRelationship::Survey', optional: true
  belongs_to :rule, class_name: 'JrcRelationship::SurveyRule', optional: true
  validates :state, inclusion: { in: %w[scheduled skipped blocked] }
  validates :source_type, :source_id, :cycle_key, :evaluation_key, :reason, :evaluated_at, presence: true

  def readonly?
    persisted?
  end
end
