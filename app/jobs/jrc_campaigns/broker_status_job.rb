class JrcCampaigns::BrokerStatusJob < ApplicationJob
  queue_as :low

  def self.enqueue_for(message)
    return unless message.additional_attributes.to_h['jrc_campaign_broker'] == true

    attributes = message.additional_attributes
    type = attributes['jrc_campaign_test_delivery_id'] ? 'test' : 'campaign'
    model = type == 'test' ? JrcCampaigns::TestDelivery : JrcCampaigns::Delivery
    id = attributes[type == 'test' ? 'jrc_campaign_test_delivery_id' : 'jrc_campaign_broker_delivery_id']
    delivery = model.find_by(id: id, inbox_id: message.inbox_id)
    return unless delivery && delivery.inbox.account_id == message.account_id && delivery.metadata['message_id'] == message.id

    set(wait: 10.seconds).perform_later(type, delivery.id)
  end

  def perform(type, id, attempt = 0)
    raise ArgumentError, 'Invalid delivery type' unless %w[test campaign].include?(type)

    delivery = (type == 'test' ? JrcCampaigns::TestDelivery : JrcCampaigns::Delivery).find_by(id: id)
    return unless delivery&.metadata.to_h&.dig('broker_connector') && delivery.metadata['message_id']

    return if local_failure?(delivery)
    return if JrcCampaigns::BrokerCallbackDeferral.hold?(delivery)

    campaign = delivery.recipient.campaign if type == 'campaign'
    connector = JrcCampaigns::BrokerConnector.for(delivery.inbox)
    unless connector && delivery.metadata['broker_connector'] == connector.public_configuration
      return uncertain!(delivery, campaign, 'Configuração do Broker alterada; reconciliar antes de qualquer reenvio.')
    end

    user = type == 'test' ? delivery.requested_by : campaign.created_by
    status = connector.receipt(user, delivery.metadata.fetch('conversation_id'), delivery.metadata.fetch('message_id'))
    delivery.update!(metadata: delivery.metadata.merge('provider_status' => status, 'status_checked_at' => Time.current.iso8601))
    if status.in?(%w[sent delivered read])
      if type == 'test'
        delivery.update!(status: 'sent', error_message: nil)
      else
        JrcCampaigns::StatusTrackerService.call(external_id: delivery.external_id, status: 'sent') if delivery.sent_at.blank?
        JrcCampaigns::DispatchStepService.new(recipient: delivery.recipient, step: delivery.step).perform
        JrcCampaigns::StatusTrackerService.call(external_id: delivery.external_id, status: status) unless status == 'sent'
      end
    elsif status.in?(%w[failed blocked])
      if type == 'test'
        delivery.update!(status: 'failed', error_message: 'Broker recusou o envio. Verifique a configuração e o histórico.')
      else
        JrcCampaigns::StatusTrackerService.call(external_id: delivery.external_id, status: 'failed', errors: ['Broker recusou o envio.'])
        JrcCampaigns::ExecutionCompletionService.new(delivery.recipient.execution).check!
      end
      campaign.pause! if campaign&.reload&.running?
      return
    elsif status == 'unknown'
      return uncertain!(delivery, campaign, 'Resultado do Broker desconhecido; reenvio automático bloqueado.')
    end
    return if status == 'read'

    if attempt >= 19 && delivery.status == 'sending'
      return uncertain!(delivery, campaign,
                        'Broker sem confirmação; reconciliar no histórico antes de reenviar.')
    end

    self.class.set(wait: 1.minute).perform_later(type, id, attempt + 1) if attempt < 19
  rescue JrcBroker::Client::Error, JrcBroker::Configuration::InvalidConfiguration, JrcBroker::CredentialStore::InvalidCredential
    if delivery && attempt < 19
      self.class.set(wait: 1.minute).perform_later(type, id, attempt + 1)
    elsif delivery
      uncertain!(delivery, campaign, 'Consulta ao Broker indisponível; reenvio automático bloqueado.')
    end
  end

  private

  def local_failure?(delivery)
    message = delivery.inbox.account.messages.find_by(id: delivery.metadata['message_id'], inbox_id: delivery.inbox_id)
    JrcCampaigns::BrokerDeliveryFailure.call(message: message, delivery: delivery)
  end

  def uncertain!(delivery, campaign, reason)
    return if delivery.status.in?(%w[sent delivered read failed])

    delivery.update!(status: 'unknown', error_message: reason)
    delivery.recipient.update!(error_message: reason) if campaign
    campaign.pause! if campaign&.reload&.running?
  end
end
