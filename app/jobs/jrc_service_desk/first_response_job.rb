# frozen_string_literal: true

class JrcServiceDesk::FirstResponseJob < ApplicationJob
  queue_as :default

  def perform(message_id, evidence = nil)
    message = Message.find_by(id: message_id)
    JrcServiceDesk::NativeResponseRecorder.new(message, evidence: evidence).call if message
  end
end
