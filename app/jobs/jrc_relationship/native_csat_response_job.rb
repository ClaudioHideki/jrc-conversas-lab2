class JrcRelationship::NativeCsatResponseJob < ApplicationJob
  queue_as :default

  def perform(response_id)
    response = CsatSurveyResponse.find_by(id: response_id)
    return unless response

    JrcRelationship::SurveyEngine.native_csat_response(response)
  end
end
