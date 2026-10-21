require 'digest'

class JrcCampaigns::EvolutionTestService
  def initialize(connector:, user:, phone_number:, step:, idempotency_key:, operator_confirmed:)
    @connector, @user, @phone_number, @step = connector, user, phone_number, step
    @idempotency_key, @operator_confirmed = idempotency_key, operator_confirmed
  end

  def perform
    raise ArgumentError, 'Confirme explicitamente o remetente e o destinatário do teste Evolution.' unless operator_confirmed == true
    raise ArgumentError, 'Chave de idempotência UUID obrigatória para o teste Evolution.' unless idempotency_key.to_s.match?(/\A[0-9a-f-]{36}\z/i)

    existing = nil
    account.with_lock do
      existing = JrcCampaigns::TestDelivery.find_by(account: account, idempotency_key: idempotency_key)
      unless existing
        unless JrcCampaigns::Consent.active.exists?(account: account, phone_number: phone_number, purpose: 'whatsapp_campaigns')
          @authorization = JrcCampaigns::TestAuthorization.available.where(account: account, inbox: connector.inbox, phone_number: phone_number).lock.first
        end
        eligibility!
        @delivery = JrcCampaigns::TestDelivery.create!(account: account, inbox: connector.inbox, requested_by: user,
                                                      idempotency_key: idempotency_key, phone_number: phone_number, payload_digest: digest,
                                                      metadata: { 'step' => step, 'connector' => connector.public_configuration })
        @authorization&.update!(consumed_at: Time.current, test_delivery: delivery)
      end
    end
    if existing
      raise ArgumentError, 'Esta chave de teste já foi usada para outra solicitação.' unless existing.payload_digest == digest && existing.requested_by_id == user.id

      return result(existing)
    end

    client.verify_sender!
    gate.reserve!
    eligibility!
    @provider_attempted = true
    external_id = client.send_message(phone_number: phone_number, **step.symbolize_keys.slice(:kind, :body, :media_url, :file_name))
    delivery.update!(status: 'sent', external_id: external_id)
    gate.complete!
    record_message
    JrcCampaigns::EvolutionStatusJob.set(wait: 1.minute).perform_later('test', delivery.id)
    result(delivery)
  rescue StandardError => e
    if delivery && delivery.external_id.blank?
      unknown = @provider_attempted && !e.is_a?(JrcCampaigns::EvolutionClient::Rejected)
      delivery.update!(status: unknown ? 'unknown' : 'failed', error_message: e.message)
      gate.halt!(e.message) if @provider_attempted
    end
    raise unless delivery
    return result(delivery) if delivery.external_id.blank?

    # An accepted send must remain idempotent even if local recording failed.
    delivery.update!(error_message: 'Enviado; registro local pendente. Não reenviar.')
    JrcCampaigns::EvolutionStatusJob.set(wait: 1.minute).perform_later('test', delivery.id)
    result(delivery)
  end

  private

  attr_reader :connector, :user, :phone_number, :step, :idempotency_key, :operator_confirmed, :delivery

  def account
    connector.inbox.account
  end

  def client
    @client ||= JrcCampaigns::EvolutionClient.new(connector)
  end

  def gate
    @gate ||= JrcCampaigns::EvolutionSafetyGate.new(connector)
  end

  def digest
    Digest::SHA256.hexdigest([connector.inbox.id, phone_number, step.to_json].to_json)
  end

  def eligibility!
    policy = JrcCampaigns::EligibilityPolicy.new(account: account, phone_number: phone_number, purpose: 'whatsapp_campaigns')
    reason = policy.safety_rejection_reason
    raise ArgumentError, reason if reason
    raise ArgumentError, 'Template Meta exige uma caixa WhatsApp oficial.' if step['kind'] == 'template'
    raise ArgumentError, 'O número remetente não pode ser o destinatário do teste.' if phone_number.delete_prefix('+') == connector.sender_number

    if @authorization
      @authorization.reload
      valid = @authorization.revoked_at.nil? && @authorization.granted_at <= Time.current && @authorization.matches_connector?(connector)
      valid &&= delivery ? @authorization.test_delivery_id == delivery.id : @authorization.consumed_at.nil?
      raise ArgumentError, 'Autorização de teste indisponível, revogada ou incompatível com o remetente.' unless valid
    else
      reason = policy.rejection_reason
      raise ArgumentError, reason if reason
    end
  end

  def record_message
    message = JrcCampaigns::EvolutionMessageRecorder.call(
      account: account, inbox: connector.inbox, phone_number: phone_number, external_id: delivery.external_id,
      kind: step['kind'], body: step['body'], media_url: step['media_url'], attributes: { 'jrc_campaign_test_delivery_id' => delivery.id }
    )
    delivery.update!(metadata: delivery.metadata.merge('message_id' => message.id))
  end

  def result(record)
    { message_id: record.external_id, test_delivery_id: record.id, status: record.status == 'sending' ? 'unknown' : record.status,
      inbox_id: connector.inbox.id, phone_number: phone_number, sender_number: connector.sender_number,
      delivery_channel: 'whatsapp', delivery_confirmed: record.metadata['provider_status'].in?(%w[delivered read]),
      error_message: record.error_message }
  end
end
