# Consumes facts only. An authenticated completion report cannot mark a
# contract signed, attach unverified files or release implementation.
class JrcBackoffice::Signatures::Notifications
  KINDS = { 'completion_reported' => 'completion_reported', 'canceled' => 'envelope_canceled', 'declined' => 'envelope_declined' }.freeze
  attr_reader :delivery

  def initialize(receipt_id:)
    @receipt = JrcBackoffice::SignatureNotification.find(receipt_id)
  end

  def call
    @delivery = nil
    @receipt.reload
    return :finished if @receipt.state == 'ignored'

    connection = @receipt.connection
    raise JrcBackoffice::Signatures::DeliveryError, 'NOTIFICATION_CONNECTION_REQUIRED' unless connection

    fact = JrcBackoffice::Signatures::Gateway.new(connection: connection).notification(receipt: @receipt)
    return finish!('ignored') unless fact[:state]

    @delivery = binding(fact.fetch(:external_id))
    return :unbound unless @delivery

    @delivery.with_lock('FOR NO KEY UPDATE') { consume!(@delivery, fact) }
  end

  private

  def binding(external_id)
    JrcBackoffice::SignatureDelivery.joins(:events).where(account_id: @receipt.account_id, connection_id: @receipt.connection_id)
                                    .where(jrc_backoffice_signature_delivery_events: { external_id: external_id, kind: 'send_confirmed',
                                                                                       account_id: @receipt.account_id,
                                                                                       connection_id: @receipt.connection_id }).first
  end

  def consume!(delivery, fact)
    @receipt.with_lock do
      next :finished if @receipt.state.in?(%w[processed ignored])
      next finish!('ignored') if obsolete?(delivery, fact)

      kind = KINDS.fetch(fact.fetch(:state))
      unless delivery.state == fact[:state]
        delivery.events.create!(account: delivery.account, connection: delivery.connection, kind: kind,
                                event_key: "notification:#{@receipt.id}", source_snapshot: JrcServiceDesk::CanonicalJson.dump(
                                  'receipt_id' => @receipt.id, 'provider_generated_at' => fact.fetch(:generated_at).iso8601(6)
                                ))
      end
      finish!('processed')
    end
  end

  def obsolete?(delivery, fact)
    return true if delivery.state.in?(%w[canceled declined]) && delivery.state != fact[:state]

    prior = delivery.events.where(kind: KINDS.values).order(id: :desc).first
    facts = prior&.snapshot || {}
    generated = facts['provider_generated_at'] || facts['observed_at']
    generated && Time.iso8601(generated) > fact.fetch(:generated_at)
  end

  def finish!(state)
    @receipt.update!(state: state)
    state.to_sym
  end
end
