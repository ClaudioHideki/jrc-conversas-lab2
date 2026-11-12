# Worker entry: actor/account/connection come from the committed admission,
# never from user-supplied job parameters. A claim is committed before POST.
class JrcBackoffice::Signatures::Dispatch
  def initialize(delivery_id:)
    @delivery = JrcBackoffice::SignatureDelivery.find(delivery_id)
    @context = JrcBackoffice::Signatures::DispatchContext.new(delivery: @delivery)
  end

  def call
    ensure_committed!
    return JrcBackoffice::Signatures::DeliveryProjection.call(@delivery) if @delivery.external_id

    bytes = claim!
    return @delivery unless bytes

    submit!(bytes)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise if @delivery.external_id

    block_unsent!('DELIVERY_ACCESS_DENIED')
    @delivery
  rescue JrcApprovals::Error, JrcBackoffice::Signatures::DeliveryError => e
    raise if @delivery.external_id || e.code == 'DISPATCH_REQUIRES_COMMITTED_INTENT'

    block_unsent!(e.code)
    @delivery
  end

  private

  def ensure_committed!
    raise JrcBackoffice::Signatures::DeliveryError, 'DISPATCH_REQUIRES_COMMITTED_INTENT' if ApplicationRecord.connection.transaction_open?
  end

  def claim!
    @delivery.account.with_lock('FOR NO KEY UPDATE') do
      request = @context.access!
      request.sales_order.with_lock('FOR NO KEY UPDATE') do
        request.with_lock('FOR NO KEY UPDATE') do
          @delivery.contract.with_lock('FOR NO KEY UPDATE') { claim_delivery! }
        end
      end
    end
  end

  def claim_delivery!
    @delivery.with_lock('FOR NO KEY UPDATE') do
      next unless @delivery.state == 'prepared'

      bytes = @context.verify!
      append!('dispatch_started', 'dispatch-claim', {})
      bytes
    end
  end

  def submit!(bytes)
    @context.access!
    source = @delivery.snapshot
    signers = source.fetch('recipients').map do |row|
      { id: row.fetch('position').to_s, name: row.fetch('name'), email: row.fetch('email'), anchor: row.fetch('anchor') }
    end
    result = JrcBackoffice::Signatures::Gateway.new(connection: @delivery.connection).send_for_signature(
      document: bytes, signers: signers, subject: 'Contrato para assinatura', transaction_id: @delivery.transaction_id
    )
    raise JrcBackoffice::Signatures::ProviderError.new(code: 'SEND_NOT_CONFIRMED', uncertain: true) unless result[:state] == 'sent'

    persist_outcome!('send_confirmed', { 'provider_state' => result.fetch(:provider_state) }, external_id: result.fetch(:external_id))
    JrcBackoffice::Signatures::DeliveryProjection.call(@delivery)
  rescue JrcBackoffice::Signatures::ProviderError => e
    persist_outcome!(e.uncertain? ? 'send_uncertain' : 'send_rejected', { 'code' => e.code })
    @delivery
  end

  def persist_outcome!(kind, facts, external_id: nil)
    @delivery.with_lock('FOR NO KEY UPDATE') do
      append!(kind, 'dispatch-outcome', facts, external_id: external_id) unless @delivery.events.exists?(event_key: 'dispatch-outcome')
    end
  end

  def block_unsent!(code)
    @delivery.with_lock('FOR NO KEY UPDATE') do
      next unless @delivery.state.in?(%w[prepared dispatching])

      append!('sender_blocked', 'dispatch-outcome', { 'code' => code }) unless @delivery.events.exists?(event_key: 'dispatch-outcome')
    end
  end

  def append!(kind, key, facts, external_id: nil)
    @delivery.events.create!(account: @delivery.account, connection: @delivery.connection, kind: kind, event_key: key,
                             external_id: external_id, source_snapshot: JrcServiceDesk::CanonicalJson.dump(facts))
  end
end
