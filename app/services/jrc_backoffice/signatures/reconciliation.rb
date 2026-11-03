# Discover an uncertain send only through its original transaction/connection.
# A committed observation reserves each read window, including after crashes.
# Empty/expired lookups never authorize another POST or release the contract.
class JrcBackoffice::Signatures::Reconciliation
  INTERVAL = 16.minutes
  WINDOW = 7.days
  TERMINAL_STATES = { 'completion_reported' => 'completion_reported', 'canceled' => 'envelope_canceled',
                      'declined' => 'envelope_declined' }.freeze

  def initialize(delivery_id:)
    @delivery = JrcBackoffice::SignatureDelivery.find(delivery_id)
    @context = JrcBackoffice::Signatures::DispatchContext.new(delivery: @delivery)
  end

  def call
    raise JrcBackoffice::Signatures::DeliveryError, 'RECONCILIATION_REQUIRES_COMMITTED_INTENT' if ApplicationRecord.connection.transaction_open?

    if @delivery.external_id
      @context.read!
      return JrcBackoffice::Signatures::DeliveryProjection.call(@delivery)
    end

    claim = claim!
    return @delivery unless claim

    discover!(claim)
    JrcBackoffice::Signatures::DeliveryProjection.call(@delivery)
    @delivery
  end

  # Bounded candidates; permission/account checks still run for every call.
  def self.candidates
    rows = JrcBackoffice::SignatureDelivery.joins(:events).group(:id).having(<<~SQL.squish, WINDOW.ago, INTERVAL.ago, INTERVAL.ago)
      MIN(jrc_backoffice_signature_delivery_events.created_at) FILTER (WHERE kind = 'dispatch_started') > ?
      AND MIN(jrc_backoffice_signature_delivery_events.created_at) FILTER (WHERE kind = 'dispatch_started') < ?
      AND COUNT(*) FILTER (WHERE kind IN ('send_confirmed', 'send_rejected', 'sender_blocked', 'canceled_before_send',
        'completion_reported', 'envelope_canceled', 'envelope_declined')) = 0
      AND (MAX(jrc_backoffice_signature_delivery_events.created_at) FILTER (WHERE kind IN ('reconciliation_started', 'reconciliation_finished')) IS NULL
        OR MAX(jrc_backoffice_signature_delivery_events.created_at) FILTER (WHERE kind IN ('reconciliation_started', 'reconciliation_finished')) < ?)
    SQL
    order = 'MAX(jrc_backoffice_signature_delivery_events.created_at) FILTER ' \
            "(WHERE kind IN ('reconciliation_started', 'reconciliation_finished')) ASC NULLS FIRST"
    rows.order(Arel.sql(order)).order(:id).limit(100)
  end

  private

  def claim!
    @delivery.with_lock('FOR NO KEY UPDATE') do
      next unless @delivery.state.in?(%w[dispatching uncertain]) && !@delivery.external_id

      started = @delivery.events.find_by!(kind: 'dispatch_started').created_at
      previous = @delivery.events.where(kind: JrcBackoffice::SignatureDeliveryEvent::OBSERVATIONS).maximum(:created_at)
      next unless started > WINDOW.ago && [started, previous].compact.max < INTERVAL.ago

      append!('reconciliation_started', "reconcile:#{SecureRandom.uuid}", {})
    end
  end

  def discover!(claim)
    @context.read!
    result = JrcBackoffice::Signatures::Gateway.new(connection: @delivery.connection).recover_send(transaction_id: @delivery.transaction_id)
    @delivery.with_lock('FOR NO KEY UPDATE') do
      apply_result!(claim, result)
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    finish!(claim, 'DELIVERY_ACCESS_DENIED')
  rescue JrcApprovals::Error, JrcBackoffice::Signatures::ProviderError, JrcBackoffice::Signatures::DeliveryError => e
    finish!(claim, e.code)
  end

  def apply_result!(claim, result)
    unless result[:found] && result[:state].in?(['waiting'] + TERMINAL_STATES.keys)
      return append!('reconciliation_finished', "#{claim.event_key}:outcome", { 'code' => 'SEND_NOT_RESOLVED' })
    end

    if @delivery.external_id && @delivery.external_id != result.fetch(:external_id)
      raise JrcBackoffice::Signatures::DeliveryError, 'RECONCILIATION_BINDING_CONFLICT'
    end

    bind!(result) unless @delivery.external_id
    append!('reconciliation_finished', "#{claim.event_key}:outcome", { 'code' => 'ENVELOPE_RECOVERED' })
  end

  def bind!(result)
    raise JrcBackoffice::Signatures::DeliveryError, 'RECONCILIATION_STATE_CONFLICT' unless @delivery.state.in?(%w[dispatching uncertain])

    facts = { 'provider_state' => result.fetch(:provider_state), 'recovered' => true, 'observed_at' => Time.current.iso8601(6) }
    append!('send_confirmed', 'reconciliation-binding', facts, external_id: result.fetch(:external_id))
    kind = TERMINAL_STATES[result[:state]]
    append!(kind, 'reconciliation-state', facts) if kind
  end

  def finish!(claim, code)
    @delivery.with_lock('FOR NO KEY UPDATE') do
      key = "#{claim.event_key}:outcome"
      append!('reconciliation_finished', key, { 'code' => code }) unless @delivery.events.exists?(event_key: key)
    end
  end

  def append!(kind, key, facts, external_id: nil)
    @delivery.events.create!(account: @delivery.account, connection: @delivery.connection, kind: kind, event_key: key,
                             external_id: external_id, source_snapshot: JrcServiceDesk::CanonicalJson.dump(facts))
  end
end
