require 'digest'

class JrcCampaigns::BrokerTestService
  def initialize(connector:, user:, phone_number:, step:, idempotency_key:, operator_confirmed:)
    @connector, @user, @phone, @step, @key, @confirmed = connector, user, phone_number, step, idempotency_key, operator_confirmed
  end

  def perform
    raise ArgumentError, 'Confirme o número remetente e o destinatário do teste.' unless @confirmed == true
    raise ArgumentError, 'Identificador do teste inválido.' unless JrcBroker::Client::UUID.match?(@key.to_s)
    account = @connector.inbox.account
    digest = Digest::SHA256.hexdigest([@connector.public_configuration, @phone, @step].to_json)
    existing = JrcCampaigns::TestDelivery.find_by(account: account, idempotency_key: @key)
    return result(existing, digest) if existing

    @connector.ready!(@user)
    # Account lock only covers local claims. No provider call takes place under it.
    account.with_lock do
      @delivery = JrcCampaigns::TestDelivery.find_by(account: account, idempotency_key: @key)
      unless @delivery
        unresolved = JrcCampaigns::TestDelivery.where(account: account, inbox: @connector.inbox, phone_number: @phone, status: %w[sending unknown])
        raise ArgumentError, 'Teste anterior pendente ou desconhecido; reconcilie o resultado antes de reenviar.' if unresolved.exists?
        reason = JrcCampaigns::EligibilityPolicy.new(account: account, phone_number: @phone, purpose: 'whatsapp_campaigns').rejection_reason
        raise ArgumentError, reason if reason

        @delivery = JrcCampaigns::TestDelivery.create!(account: account, inbox: @connector.inbox, requested_by: @user, phone_number: @phone,
                                                       idempotency_key: @key, payload_digest: digest, status: 'sending',
                                                       metadata: { 'broker_connector' => @connector.public_configuration })
        JrcCampaigns::BrokerMessageSender.call(delivery: @delivery, user: @user, phone_number: @phone, step: @step,
                                              attributes: { 'campaign_id' => "test:#{@delivery.id}", 'jrc_campaign_test_delivery_id' => @delivery.id })
      end
    end
    JrcCampaigns::BrokerStatusJob.set(wait: 10.seconds).perform_later('test', @delivery.id)
    result(@delivery, digest)
  end

  private

  def result(record, digest)
    unless record.requested_by_id == @user.id && record.payload_digest == digest && record.inbox_id == @connector.inbox.id
      raise ArgumentError, 'Identificador já utilizado em outro teste.'
    end

    { test_delivery_id: record.id, message_id: record.external_id, status: record.status, inbox_id: record.inbox_id,
      delivery_channel: 'whatsapp', delivery_confirmed: record.metadata['provider_status'].in?(%w[delivered read]), error_message: record.error_message }
  end
end
