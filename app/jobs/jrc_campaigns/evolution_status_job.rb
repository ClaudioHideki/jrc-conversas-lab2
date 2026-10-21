class JrcCampaigns::EvolutionStatusJob < ApplicationJob
  queue_as :low

  def perform(type, delivery_id, attempt = 0)
    delivery = type == 'test' ? JrcCampaigns::TestDelivery.find_by(id: delivery_id) : JrcCampaigns::Delivery.find_by(id: delivery_id)
    return unless delivery&.external_id.present?

    connector = JrcCampaigns::EvolutionConnector.for(delivery.inbox)
    return unless connector
    expected_connector = delivery.metadata[type == 'test' ? 'connector' : 'evolution_connector']
    return unless expected_connector == connector.public_configuration

    raw_id = type == 'test' ? delivery.external_id : delivery.metadata['evolution_id']
    return if raw_id.blank?

    if type == 'test' && delivery.metadata['message_id'].blank?
      step = delivery.metadata.fetch('step')
      message = JrcCampaigns::EvolutionMessageRecorder.call(
        account: delivery.account, inbox: delivery.inbox, phone_number: delivery.phone_number, external_id: raw_id,
        kind: step['kind'], body: step['body'], media_url: step['media_url'], attributes: { 'jrc_campaign_test_delivery_id' => delivery.id }
      )
      delivery.update!(metadata: delivery.metadata.merge('message_id' => message.id))
    end

    status = JrcCampaigns::EvolutionClient.new(connector).status(raw_id)
    metadata = delivery.metadata.to_h.merge('provider_status' => status || 'unconfirmed', 'status_checked_at' => Time.current.iso8601)
    delivery.update!(metadata: metadata)
    if status
      JrcCampaigns::StatusTrackerService.call(external_id: delivery.external_id, status: status) if type == 'campaign'
      message = delivery.inbox.account.messages.find_by(id: metadata['message_id'], inbox_id: delivery.inbox_id)
      Messages::StatusUpdateService.new(message, status, status == 'failed' ? 'Evolution: envio recusado.' : nil).perform if message
      if status == 'failed'
        JrcCampaigns::EvolutionSafetyGate.new(connector).halt!('Evolution confirmou falha de entrega; revisar antes de retomar.')
        campaign = delivery.recipient.campaign if type == 'campaign'
        campaign.pause! if campaign&.reload&.running?
      end
    end
    self.class.set(wait: 1.minute).perform_later(type, delivery_id, attempt + 1) if attempt < 19 && !status.in?(%w[read failed])
  rescue JrcCampaigns::EvolutionClient::Rejected, JrcCampaigns::EvolutionClient::UnknownResult
    # Only the read-only status request can be retried. Never repeat send_message.
    self.class.set(wait: 1.minute).perform_later(type, delivery_id, attempt + 1) if attempt < 19
  end
end
