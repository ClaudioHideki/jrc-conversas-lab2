# Only the explicit campaign resume action can renew an exhausted safe lease.
class JrcCampaigns::BrokerRecoveryResume
  def initialize(recipient:, step:)
    @recipient = recipient
    @step = step
    @campaign = recipient.campaign
  end

  def perform
    delivery = recipient.deliveries.find_by(step: step)
    return unless delivery&.metadata.to_h&.dig('recovery_exhausted') == true

    delivery.with_lock do
      message = campaign.account.messages.find_by(id: delivery.metadata['message_id']) if delivery.metadata['message_id']
      message ? message.with_lock { reset_safe_budget(delivery, message) } : reset_safe_budget(delivery, nil)
    end
  end

  private

  attr_reader :recipient, :step, :campaign

  def reset_safe_budget(delivery, message)
    return unless valid_state?(delivery) && approved_route?(delivery)
    return unless message ? JrcCampaigns::BrokerCallbackDeferral.pending?(delivery) : delivery.external_id.blank?

    token = SecureRandom.uuid
    JrcCampaigns::BrokerRecoveryService.enqueue_watchdog(delivery.id, token)
    metadata = delivery.metadata.to_h.except('recovery_exhausted').merge('dispatch_token' => token, 'recovery_attempts' => 0)
    delivery.update!(metadata: metadata, error_message: nil)
    recipient.update!(error_message: nil)
  end

  def valid_state?(delivery)
    delivery.sending? && delivery.sent_at.nil? && campaign.reload.running? && !recipient.reload.status.in?(%w[failed canceled skipped]) &&
      [delivery.inbox.account_id, delivery.inbox_id, delivery.step.campaign_id] == [campaign.account_id, recipient.inbox_id, campaign.id]
  end

  def approved_route?(delivery)
    return false unless JrcCampaigns::ApprovalService.new(campaign).locally_valid?

    connector = JrcCampaigns::BrokerConnector.for(delivery.inbox.reload)
    connector && connector.public_configuration == delivery.metadata['broker_connector']
  end
end
