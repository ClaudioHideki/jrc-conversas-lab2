class JrcRelationship::SurveyVersion < ApplicationRecord
  self.table_name = 'jrc_relationship_survey_versions'
  belongs_to :account
  belongs_to :actor, class_name: 'User', optional: true
  validates :entity_type, inclusion: { in: %w[JrcRelationship::SurveyDefinition JrcRelationship::SurveyRule] }
  validates :entity_id, :version, :payload, presence: true

  def readonly?
    persisted?
  end
end
