# frozen_string_literal: true

class JrcServiceDesk::NotificationReconciliationJob < ApplicationJob
  queue_as :high

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message

    row = JrcServiceDesk::NotificationDelivery.find_by(id: message.content_attributes['service_desk_delivery_id'],
                                                       account_id: message.account_id, message_id: message.id,
                                                       conversation_id: message.conversation_id)
    return unless row

    JrcServiceDesk::NotificationReceipt.new(row).call
  end
end
