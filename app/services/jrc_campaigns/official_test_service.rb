require 'digest'

class JrcCampaigns::OfficialTestService
  def initialize(inbox:, user:, phone_number:, step:, renderer:, idempotency_key:, operator_confirmed:)
    @inbox = inbox
    @user = user
    @phone = phone_number
    @step = step
    @renderer = renderer
    @key = idempotency_key
    @confirmed = operator_confirmed
  end

  def perform
    @created = false
    raise ArgumentError, 'Teste oficial exige uma caixa Channel::Whatsapp.' unless @inbox.channel_type == 'Channel::Whatsapp'

    JrcCampaigns::OfficialMetaRoute.assert!(@inbox)
    @attempted = false
    raise ArgumentError, 'Confirme explicitamente o remetente e destinatário do teste.' unless @confirmed == true
    raise ArgumentError, 'Chave UUID de idempotência obrigatória.' unless @key.to_s.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i)

    account.with_lock do
      @delivery = JrcCampaigns::TestDelivery.find_by(account: account, idempotency_key: @key)
      if @delivery
        unless @delivery.payload_digest == digest && @delivery.requested_by_id == @user.id
          raise ArgumentError,
                'Identificador já usado em outro teste.'
        end

        return result
      end
      eligibility!
      @delivery = JrcCampaigns::TestDelivery.create!(account: account, inbox: @inbox, requested_by: @user, phone_number: @phone,
                                                     idempotency_key: @key, payload_digest: digest, status: 'sending',
                                                     metadata: { 'connector' => 'official', 'template' => @step['template_name'],
                                                                 'language' => @step['template_language'], 'step' => @step })
      @created = true
    end
    info = JrcCampaigns::TemplateConfiguration.new(inbox: @inbox, step: @step).payload(renderer: @renderer) if @step['kind'] == 'template'
    proxy = JrcCampaigns::ProviderMessageProxy.new(kind: @step['kind'], body: @renderer.render(@step['body']),
                                                   media_url: @step['media_url'], file_name: @step['file_name'])
    eligibility!
    @attempted = true
    external_id = if info
                    @inbox.channel.send_template(@phone, info, proxy)
                  else
                    @inbox.channel.send_message(@phone, proxy)
                  end
    if external_id.blank?
      failed = proxy.status.to_s == 'failed'
      @delivery.update!(status: failed ? 'failed' : 'unknown', failed_at: failed ? Time.current : nil,
                        error_code: proxy.provider_response.to_h.dig('error', 'code'),
                        metadata: @delivery.metadata.merge('provider_response' => proxy.provider_response.to_h),
                        error_message: proxy.external_error.presence || 'Resultado desconhecido.')
    else
      held = proxy.provider_response.to_h['message_status'] == 'held_for_quality_assessment'
      @delivery.with_lock do
        @delivery.update!(external_id: external_id, accepted_at: Time.current, status: held ? 'held' : 'accepted',
                          metadata: @delivery.metadata.merge('provider_response' => proxy.provider_response.to_h))
      end
      JrcCampaigns::MetaStatusService.replay(inbox: @inbox, external_id: external_id)
    end
    result
  rescue StandardError => e
    raise unless @created

    if @delivery.external_id.blank?
      @delivery.update!(status: @attempted ? 'unknown' : 'failed',
                        error_message: 'Não foi possível concluir o teste. Verifique a configuração e o histórico.')
    end
    Rails.logger.warn("[CAMPAIGN_META_TEST] inbox_id=#{@inbox.id} test_id=#{@delivery.id} error_class=#{e.class}")
    result
  end

  private

  def account
    @inbox.account
  end

  def digest
    Digest::SHA256.hexdigest([@inbox.id, @phone, @step.to_json].to_json)
  end

  def eligibility!
    policy = JrcCampaigns::EligibilityPolicy.new(account: account, phone_number: @phone, purpose: 'whatsapp_campaigns')
    reason = policy.rejection_reason
    raise ArgumentError, reason if reason

    policy.freeform_conversation!(@inbox) unless @step['kind'] == 'template'
  end

  def result
    @delivery.reload
    { test_delivery_id: @delivery.id, message_id: @delivery.external_id, inbox_id: @inbox.id, phone_number: @phone,
      status: @delivery.status, connector: 'official', delivery_channel: 'whatsapp', delivery_confirmed: @delivery.delivered_at.present?,
      error_code: @delivery.error_code, error_message: @delivery.error_message }
  end
end
