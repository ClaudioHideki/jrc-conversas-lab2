class JrcCampaigns::BrokerRecoveryJob < ApplicationJob
  queue_as :low

  def perform(delivery_id, dispatch_token)
    delivery = JrcCampaigns::Delivery.find_by(id: delivery_id)
    JrcCampaigns::BrokerRecoveryService.new(delivery).perform(dispatch_token) if delivery
  end
end
