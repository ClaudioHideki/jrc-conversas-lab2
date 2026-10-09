class JrcRelationship::SurveyReceiptJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    JrcRelationship::SurveyMessageExecution.receipt(message) if message
  end
end
