# frozen_string_literal: true

class JrcNicoHelpdeskMailer < ApplicationMailer
  def daily_report
    authorized_message
  end

  def event_alert
    authorized_message
  end

  private

  def authorized_message
    receipt = JrcNico::Helpdesk::EmailClaim.new(JrcNico::Helpdesk::DeliveryReceipt.find(params.fetch(:receipt_id))).verify!
    source = receipt.source
    address = JrcNico::Helpdesk::DeliveryAuthorization.new(source, receipt.recipient).email!
    message = mail(to: address, subject: JrcNico::Helpdesk::EmailPointer.subject(source), content_type: 'text/plain',
                   body: JrcNico::Helpdesk::EmailPointer.url(source))
    message.delivery_handler = JrcNico::Helpdesk::EmailTransport.new(receipt)
    message.raise_delivery_errors = true
    message
  end

  def handle_smtp_exceptions(_error)
    raise JrcNico::Helpdesk::EmailTransport::Uncertain, 'MAIL_TRANSPORT_UNCERTAIN', cause: nil
  end
end
