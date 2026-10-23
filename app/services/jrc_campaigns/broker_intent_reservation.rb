class JrcCampaigns::BrokerIntentReservation
  def initialize(message)
    @message = message
  end

  def prepare!(payload)
    @message.reload
    return unless campaign_message?(payload)

    delivery, user, campaign_id = trusted_delivery!
    connector = current_connector!(delivery)
    validate_destination!(delivery)
    unless @message.additional_attributes['jrc_campaign_intent_id']
      intent_id = reserve!(connector, delivery, user, campaign_id)
      persist!(intent_id, delivery)
    end
    payload[:additional_attributes] = @message.reload.additional_attributes
  end

  private

  def campaign_message?(payload)
    marked_message = @message.additional_attributes['jrc_campaign_broker'] == true
    marked_payload = payload[:additional_attributes].to_h['jrc_campaign_broker'] == true
    reject! if marked_payload && !marked_message
    marked_message
  end

  def current_connector!(delivery)
    connector = JrcCampaigns::BrokerConnector.for(@message.inbox)
    reject! unless connector && delivery.metadata['broker_connector'] == connector.public_configuration
    connector
  end

  def reserve!(connector, delivery, user, campaign_id)
    # The native message and its correlation already committed. No DB lock spans HTTP.
    transport = connector.ready!(user)
    body = { messageId: @message.id, conversationId: @message.conversation.display_id, campaignId: campaign_id,
             kind: message_kind, text: @message.content.to_s, destinationRevision: transport.fetch('destinationRevision'),
             identityRevision: transport.fetch('identityRevision'), ownerRevision: transport.fetch('ownerRevision') }
    type = delivery.is_a?(JrcCampaigns::TestDelivery) ? 'test' : 'campaign'
    response = connector.context(user).client.campaign_intent(connector.binding.integration_id, body, key: "#{type}:#{delivery.id}")
    validated_intent_id(response)
  end

  def validated_intent_id(response)
    valid = response['protocol'] == JrcCampaigns::BrokerConnector::PROTOCOL && response['state'] == 'RESERVED' &&
            JrcBroker::Client::UUID.match?(response['intentId'].to_s) && [true, false].include?(response['replayed'])
    raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE' unless valid

    response.fetch('intentId')
  end

  def persist!(intent_id, delivery)
    @message.with_lock do
      trusted_delivery!
      validate_destination!(delivery.reload)
      current_connector!(delivery)
      existing = @message.additional_attributes['jrc_campaign_intent_id']
      reject! if existing && existing != intent_id
      # Correlation only: do not emit a second message_updated callback while preparing the original callback.
      @message.update_columns(additional_attributes: @message.additional_attributes.merge('jrc_campaign_intent_id' => intent_id)) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def trusted_delivery!
    attrs = @message.additional_attributes
    test = attrs['jrc_campaign_test_delivery_id'].present?
    model = test ? JrcCampaigns::TestDelivery : JrcCampaigns::Delivery
    delivery = model.find_by(id: attrs[test ? 'jrc_campaign_test_delivery_id' : 'jrc_campaign_broker_delivery_id'], inbox_id: @message.inbox_id)
    reject! unless correlated?(delivery)
    user, campaign_id = delivery_actor!(delivery, test)
    reject! unless valid_message?(user, campaign_id)
    [delivery, user, campaign_id]
  end

  def correlated?(delivery)
    delivery && delivery.inbox.account_id == @message.account_id && delivery.metadata['message_id'] == @message.id
  end

  def delivery_actor!(delivery, test)
    return [delivery.requested_by, "test:#{delivery.id}"] if test

    campaign = delivery.recipient.campaign
    reject! unless campaign.running?
    [campaign.created_by, campaign.id.to_s]
  end

  def valid_message?(user, campaign_id)
    user && @message.sender == user && @message.outgoing? && !@message.private? &&
      @message.additional_attributes['campaign_id'].to_s == campaign_id
  end

  def validate_destination!(delivery)
    phone = delivery.is_a?(JrcCampaigns::TestDelivery) ? delivery.phone_number : delivery.recipient.phone_number
    conversation = @message.conversation.reload
    reject! unless canonical_conversation?(conversation)
    contact = conversation.contact
    reject! unless canonical_recipient?(delivery, contact, phone)

    policy = JrcCampaigns::EligibilityPolicy.new(account: @message.account, phone_number: phone, contact: contact)
    reject! if policy.rejection_reason
  end

  def canonical_conversation?(conversation)
    link = conversation.contact_inbox
    link && [conversation.account_id, conversation.inbox_id] == [@message.account_id, @message.inbox_id] &&
      conversation.contact.account_id == @message.account_id &&
      [link.contact_id, link.inbox_id] == [conversation.contact_id, @message.inbox_id] && link.source_id.present?
  end

  def canonical_recipient?(delivery, contact, phone)
    return false unless JrcCampaigns::PhoneNormalizer.call(contact.phone_number) == JrcCampaigns::PhoneNormalizer.call(phone)
    return true if delivery.is_a?(JrcCampaigns::TestDelivery)

    recipient = delivery.recipient
    [recipient.inbox_id, recipient.contact_id] == [@message.inbox_id, contact.id]
  end

  def message_kind
    attachments = @message.attachments.to_a
    return 'text' if attachments.empty?

    reject! unless attachments.one?
    { 'image' => 'image', 'video' => 'video', 'audio' => 'audio', 'file' => 'document' }.fetch(attachments.first.file_type) { reject! }
  end

  def reject!
    raise JrcBroker::WebhookDelivery::ContextChanged
  end
end
