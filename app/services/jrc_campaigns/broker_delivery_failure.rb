class JrcCampaigns::BrokerDeliveryFailure
  CODES = %w[JRC_BROKER_DELIVERY_REJECTED JRC_BROKER_DELIVERY_CONTEXT_CHANGED JRC_BROKER_DELIVERY_UNAVAILABLE].freeze
  REJECTED = 'Broker recusou o envio. Verifique a configuração e o histórico.'.freeze
  UNCERTAIN = 'Resultado do envio ao Broker incerto; reconcilie o histórico antes de reenviar.'.freeze

  def self.call(message:, delivery: nil, failure_code: nil)
    new(message, delivery, failure_code).call
  end

  def initialize(message, delivery, failure_code)
    @message = message
    @delivery = delivery
    @failure_code = failure_code
  end

  def call
    return false unless @message && @message.additional_attributes.to_h['jrc_campaign_broker'] == true
    return false unless @failure_code || @message.failed?

    @delivery ||= find_delivery
    return false unless correlated?

    @delivery.with_lock { @message.with_lock { reconcile_locked } }
  end

  private

  def reconcile_locked
    return false unless correlated?
    return true if confirmed?

    mark_message_failed
    return false unless @message.failed? && CODES.include?(@message.external_error)
    return false unless %w[sending unknown failed].include?(@delivery.status)

    reconcile unless %w[unknown failed].include?(@delivery.status)
    pause_campaign
    true
  end

  def find_delivery
    attrs = @message.additional_attributes
    test = attrs['jrc_campaign_test_delivery_id'].present?
    model = test ? JrcCampaigns::TestDelivery : JrcCampaigns::Delivery
    model.find_by(id: attrs[test ? 'jrc_campaign_test_delivery_id' : 'jrc_campaign_broker_delivery_id'], inbox_id: @message.inbox_id)
  end

  def correlated?
    return false unless @delivery && @message.outgoing? && !@message.private?
    return false unless @message.additional_attributes.to_h['jrc_campaign_broker'] == true
    return false unless same_route?

    actor, campaign_id, delivery_id = delivery_context
    return false unless actor

    [@message.sender, @message.additional_attributes['campaign_id'].to_s, delivery_id] == [actor, campaign_id, @delivery.id]
  end

  def same_route?
    actual = [@delivery.inbox.account_id, @delivery.inbox_id, @delivery.metadata['message_id'],
              @delivery.metadata['conversation_id'], @delivery.external_id]
    actual == [@message.account_id, @message.inbox_id, @message.id, @message.conversation.display_id,
               "broker:#{@message.account_id}:#{@message.inbox_id}:#{@message.id}"]
  end

  def delivery_context
    attrs = @message.additional_attributes
    if @delivery.is_a?(JrcCampaigns::TestDelivery)
      return [] unless @delivery.account_id == @message.account_id

      return [@delivery.requested_by, "test:#{@delivery.id}", attrs['jrc_campaign_test_delivery_id']]
    end

    campaign = @delivery.recipient.campaign
    return [] unless campaign.account_id == @message.account_id && @delivery.recipient.inbox_id == @message.inbox_id

    [campaign.created_by, campaign.id.to_s, attrs['jrc_campaign_broker_delivery_id']]
  end

  def confirmed?
    %w[sent delivered read].include?(@delivery.status) ||
      (@delivery.respond_to?(:sent_at) && [@delivery.sent_at, @delivery.delivered_at, @delivery.read_at].any?(&:present?))
  end

  def mark_message_failed
    return unless CODES.include?(@failure_code) && !@message.delivered? && !@message.read?

    Messages::StatusUpdateService.new(@message, 'failed', @failure_code).perform
  end

  def pause_campaign
    return if @delivery.is_a?(JrcCampaigns::TestDelivery)

    campaign = @delivery.recipient.campaign
    now = Time.current
    # Compare and set after reconciliation so a concurrent cancellation remains terminal.
    JrcCampaigns::Campaign.where(id: campaign.id, account_id: @message.account_id, status: 'running')
                          .update_all(status: 'paused', paused_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
  end

  def reconcile
    proof = JrcBroker::WebhookDiagnostic.new(@message).read
    rejected = JrcBroker::WebhookDiagnostic.rejected?(proof)
    proof = { 'version' => 0, 'phase' => 'unknown', 'outcome' => 'unknown' } if proof.empty?
    @delivery.update!(metadata: @delivery.metadata.to_h.merge('broker_failure' => proof))
    if rejected && @delivery.is_a?(JrcCampaigns::Delivery)
      JrcCampaigns::StatusTrackerService.call(external_id: @delivery.external_id, status: 'failed', errors: [REJECTED])
    else
      @delivery.update!(status: rejected ? 'failed' : 'unknown', error_message: rejected ? REJECTED : UNCERTAIN)
      @delivery.recipient.update!(error_message: UNCERTAIN) if @delivery.is_a?(JrcCampaigns::Delivery)
    end
  end
end
