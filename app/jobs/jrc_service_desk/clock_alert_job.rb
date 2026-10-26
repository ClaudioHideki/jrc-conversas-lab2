# frozen_string_literal: true

class JrcServiceDesk::ClockAlertJob < ApplicationJob
  queue_as :default
  self.log_arguments = false

  def perform(id)
    row = JrcServiceDesk::ClockAlertDelivery.find(id)
    claimed = row.with_lock do
      next false unless row.state == 'queued'

      reason = JrcServiceDesk::ClockAlerts.blocker(row)
      if reason
        row.update!(state: 'blocked', reason: reason)
        next false
      end
      row.update!(state: 'dispatching', dispatch_started_at: Time.current, attempts: row.attempts + 1)
      true
    end
    return unless claimed

    if (reason = JrcServiceDesk::ClockAlerts.blocker(row.reload))
      row.update!(state: 'blocked', reason: reason)
      return
    end
    if row.channel == 'in_app'
      row.with_lock do
        notification = Notification.create!(account: row.account, user: row.recipient_account_user.user, primary_actor: row.ticket,
                                            notification_type: 'service_desk_clock', meta: { 'clock_alert_delivery_id' => row.id, 'percent' => row.ticket_event.data['percent'] })
        row.update!(notification: notification, state: 'accepted', accepted_at: Time.current, reason: 'in_app_persisted')
      end
    else
      delivered = JrcServiceDesk::ClockAlertMailer.with(account: row.account).alert(row.id).deliver_now
      row.update!(state: delivered ? 'accepted' : 'unknown', accepted_at: delivered && Time.current,
                  reason: delivered ? 'smtp_accepted_not_delivery_confirmation' : 'provider_result_unverified')
    end
  rescue JrcServiceDesk::ClockAlertMailer::Rejected
    row&.update!(state: 'failed', reason: 'smtp_rejected')
  rescue StandardError
    row&.with_lock { row.update!(state: 'unknown', reason: 'provider_result_unknown') unless %w[accepted blocked].include?(row.state) }
  end
end
