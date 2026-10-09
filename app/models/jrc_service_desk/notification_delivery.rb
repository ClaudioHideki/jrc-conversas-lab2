# frozen_string_literal: true

class JrcServiceDesk::NotificationDelivery < JrcServiceDesk::TicketRecord
  belongs_to :ticket_note, class_name: 'JrcServiceDesk::TicketNote', optional: true
  belongs_to :ticket_event, class_name: 'JrcServiceDesk::TicketEvent', optional: true
  belongs_to :original_delivery, class_name: 'JrcServiceDesk::NotificationDelivery', optional: true
  belongs_to :notification_policy_version, class_name: 'JrcServiceDesk::NotificationPolicyVersion', optional: true
  belongs_to :execution_membership, class_name: 'JrcServiceDesk::UnitMembership'
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true
  validates :state, inclusion: { in: %w[blocked queued dispatching sent delivered read failed unknown] }
  validates :channel, inclusion: { in: %w[email whatsapp] }
  validates :attempt_number, numericality: { only_integer: true, greater_than: 0 }
  validate :references_are_consistent
  after_create_commit :schedule_delivery

  private

  def references_are_consistent
    %i[ticket_note ticket_event original_delivery execution_membership notification_policy_version].each { |key| validate_unit_reference(key) }
    %i[conversation message].each { |key| validate_account_reference(key) }
    %i[ticket_note ticket_event original_delivery].each { |key| validate_origin_ticket(key) }
    errors.add(:base, 'requires exactly one persisted origin') unless ticket_note.present? != ticket_event.present?
    validate_message_conversation
  end

  def validate_origin_ticket(key)
    origin = public_send(key)
    errors.add(key, 'must belong to the same ticket') if origin && origin.ticket_id != ticket_id
  end

  def validate_message_conversation
    errors.add(:message, 'must belong to the selected conversation') if message && message.conversation_id != conversation_id
  end

  def schedule_delivery
    JrcServiceDesk::NotificationDeliveryJob.perform_later(id) if state == 'queued'
  end
end
