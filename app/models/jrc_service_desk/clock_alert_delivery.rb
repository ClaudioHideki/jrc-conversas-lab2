# frozen_string_literal: true

class JrcServiceDesk::ClockAlertDelivery < JrcServiceDesk::TicketRecord
  belongs_to :ticket_event, class_name: 'JrcServiceDesk::TicketEvent'
  belongs_to :recipient_account_user, class_name: 'AccountUser'
  belongs_to :notification, optional: true
  validates :channel, inclusion: { in: %w[in_app email] }
  validates :state, inclusion: { in: %w[queued dispatching accepted blocked failed unknown] }
  validates :channel, uniqueness: { scope: [:ticket_event_id, :recipient_account_user_id] }
  validate do
    validate_unit_reference(:ticket_event)
    validate_account_reference(:recipient_account_user)
    errors.add(:ticket_event, 'must belong to ticket') if ticket_event && ticket_event.ticket_id != ticket_id
  end
  after_update_commit { JrcServiceDesk::ClockAlertJob.perform_later(id) if previous_changes.key?('state') && state == 'queued' }
  after_create_commit { JrcServiceDesk::ClockAlertJob.perform_later(id) }
end
