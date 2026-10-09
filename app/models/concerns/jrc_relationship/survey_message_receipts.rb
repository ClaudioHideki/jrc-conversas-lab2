module JrcRelationship::SurveyMessageReceipts
  extend ActiveSupport::Concern

  included do
    after_update_commit :queue_relationship_survey_receipt
  end

  private

  def queue_relationship_survey_receipt
    return unless content_attributes['relationship_survey_id'] && (previous_changes.key?('status') || previous_changes.key?('source_id'))

    JrcRelationship::SurveyReceiptJob.perform_later(id)
  end
end
