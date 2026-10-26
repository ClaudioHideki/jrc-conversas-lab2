# frozen_string_literal: true

class JrcRelationship::SurveyModelDraft < ApplicationRecord
  self.table_name = 'jrc_relationship_survey_model_drafts'
  belongs_to :account
  belongs_to :unit, class_name: 'JrcServiceDesk::Unit'
  belongs_to :creator, class_name: 'User'
  belongs_to :definition, class_name: 'JrcRelationship::SurveyDefinition', optional: true
  validates :code, format: { with: /\A[a-z0-9_-]{1,32}\z/ }, uniqueness: { scope: %i[account_id unit_id] }
  validate :consistent_scope
  validate :bounded_draft

  private

  def consistent_scope
    errors.add(:unit, 'wrong account') if unit && unit.account_id != account_id
    errors.add(:definition, 'wrong account') if definition && definition.account_id != account_id
    return unless persisted? && (account_id_changed? || unit_id_changed? || code_changed? || creator_id_changed?)

    errors.add(:base, 'model identity is immutable; duplicate to change unit')
  end

  def bounded_draft
    [payload, published_payload].each do |data|
      errors.add(:payload, 'must be a bounded object') unless data.is_a?(Hash) && data.to_json.bytesize <= 100_000
    end
  end
end
