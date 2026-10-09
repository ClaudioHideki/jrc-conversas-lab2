# frozen_string_literal: true

class JrcNico::Helpdesk::EmailDelivery
  def initialize(receipt)
    @receipt = receipt
  end

  def call
    # An outer transaction's savepoint is not a durable delivery claim.
    return block_for_transaction! if @receipt.class.connection.transaction_open?
    return @receipt unless claim!

    send_claim!
    @receipt
  end

  private

  def block_for_transaction!
    @receipt.with_lock do
      JrcNico::Helpdesk::DeliveryAuthorization.new(@receipt.source, @receipt.recipient).call
      next if JrcNico::Helpdesk::Delivery::TERMINAL.include?(@receipt.state)

      @receipt.update!(state: 'blocked', reason: 'durable_commit_required')
    end
    @receipt
  end

  def claim!
    @receipt.with_lock do
      JrcNico::Helpdesk::DeliveryAuthorization.new(@receipt.source, @receipt.recipient).email!
      next false if %w[dispatching sent delivered unknown failed].include?(@receipt.state)

      fingerprints = JrcNico::Helpdesk::EmailClaim.new(@receipt).fingerprints
      now = Time.current
      @receipt.update!(fingerprints.merge(state: 'dispatching', reason: nil, claim_token: SecureRandom.uuid,
                                          attempt_number: @receipt.attempt_number + 1, attempted_at: now, dispatching_at: now))
      true
    end
  rescue Pundit::NotAuthorizedError, ArgumentError
    @receipt.with_lock do
      raise Pundit::NotAuthorizedError if JrcNico::Helpdesk::Delivery::TERMINAL.include?(@receipt.state)

      reason = @receipt.source_type == 'event' ? 'verified_event_recipient_and_origin_required' : 'verified_daily_recipient_and_origin_required'
      @receipt.update!(state: 'blocked', reason: reason)
    end
    false
  end

  def send_claim!
    action = @receipt.source_type == 'event' ? :event_alert : :daily_report
    message = JrcNicoHelpdeskMailer.with(receipt_id: @receipt.id).public_send(action).deliver_now
    @receipt.with_lock do
      @receipt.update!(state: 'sent', sent_at: Time.current, remote_id: message.message_id,
                       evidence: { 'adapter' => 'action_mailer', 'outcome' => 'accepted' })
    end
  rescue JrcNico::Helpdesk::EmailTransport::Blocked, Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    @receipt.with_lock { @receipt.update!(state: 'blocked', reason: 'delivery_authorization_revoked') }
  rescue StandardError
    @receipt.with_lock { @receipt.update!(state: 'unknown', reason: 'mail_transport_uncertain') }
  end
end
