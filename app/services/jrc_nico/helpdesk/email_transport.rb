# frozen_string_literal: true

# Scoped replacement of raw deliver.action_mailer instrumentation for this message only.
class JrcNico::Helpdesk::EmailTransport
  class Uncertain < StandardError; end
  class Blocked < StandardError; end

  def initialize(receipt)
    @id = receipt.id
    @token = receipt.claim_token
  end

  def deliver_mail(mail)
    receipt = JrcNico::Helpdesk::EmailClaim.new(JrcNico::Helpdesk::DeliveryReceipt.find(@id)).verify!
    raise Blocked, 'DELIVERY_DISABLED' unless mail.perform_deliveries && receipt.claim_token == @token

    verify_message!(mail, receipt)

    yield
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise Blocked, 'DELIVERY_AUTHORIZATION_REVOKED', cause: nil
  rescue Blocked
    raise
  rescue StandardError
    raise Uncertain, 'MAIL_TRANSPORT_UNCERTAIN', cause: nil
  end

  private

  def verify_message!(mail, receipt)
    address = JrcNico::Helpdesk::DeliveryAuthorization.new(receipt.source, receipt.recipient).email!
    valid = mail.to == [address] && Array(mail.cc).empty? && Array(mail.bcc).empty? && mail.attachments.empty?
    valid &&= mail.body.decoded.to_s.strip == JrcNico::Helpdesk::EmailPointer.url(receipt.source)
    valid &&= mail.subject == JrcNico::Helpdesk::EmailPointer.subject(receipt.source)
    raise Blocked, 'DELIVERY_MESSAGE_CHANGED' unless valid
  end
end
