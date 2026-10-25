# frozen_string_literal: true

class JrcServiceDesk::ClockAlertMailer < ApplicationMailer
  class Rejected < StandardError; end

  def alert(delivery_id)
    row = JrcServiceDesk::ClockAlertDelivery.find(delivery_id)
    raise Pundit::NotAuthorizedError if JrcServiceDesk::ClockAlerts.blocker(row)

    percent = row.ticket_event.data.fetch('percent')
    url = "#{ENV.fetch('FRONTEND_URL')}/app/accounts/#{row.account_id}/service-desk/tickets/#{row.ticket_id}"
    mail(to: row.recipient_account_user.user.email, subject: "OLA Service Desk ##{row.ticket_id} — #{percent}%") do |format|
      format.text do
        render plain: "OLA interno do chamado ##{row.ticket_id}: limite de #{percent}% atingido.
#{url}"
      end
    end
  end

  private

  # Keep exception text/SMTP credentials out of logs; the durable caller records
  # unknown effects and never retries an uncertain SMTP result automatically.
  def handle_smtp_exceptions(error)
    raise Rejected, 'CLOCK_ALERT_SMTP_REJECTED' if error.is_a?(Net::SMTPFatalError)

    raise IOError, 'CLOCK_ALERT_SMTP_RESULT_UNKNOWN'
  end
end
