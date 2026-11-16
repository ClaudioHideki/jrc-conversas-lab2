class Messages::StatusUpdateService
  attr_reader :message, :status, :external_error

  def initialize(message, status, external_error = nil)
    @message = message
    @status = status
    @external_error = external_error
  end

  def perform
    tracked = message.content_attributes.to_h['jrc_broker_outbound'].is_a?(Hash) ||
              JrcBrokerWebhookObligation.exists?(message_id: message.id)
    return perform_update unless tracked

    message.with_lock { perform_update }
  end

  private

  def perform_update
    return false unless valid_status_transition?

    update_message_status
    JrcCampaigns::BrokerStatusJob.enqueue_for(message)
    true
  end

  def update_message_status
    # Update status and set external_error only when failed
    message.update!(
      status: status,
      external_error: (status == 'failed' ? external_error : nil)
    )
  end

  def valid_status_transition?
    return false unless Message.statuses.key?(status)
    return false if broker_receipt_downgrade?

    # Don't allow changing from 'read' to 'delivered'
    return false if message.read? && status == 'delivered'

    true
  end

  def broker_receipt_downgrade?
    receipt = message.content_attributes.to_h['jrc_broker_outbound']
    return false unless receipt.is_a?(Hash) && receipt['version'] == 1 &&
                        receipt['canonical_message_id'].present? && receipt['provider_message_id'].present?

    rank = JrcBroker::OutboundReceipt::RANK
    rank.fetch(status.upcase, 0) < rank.fetch(receipt['state'], 0)
  end
end
