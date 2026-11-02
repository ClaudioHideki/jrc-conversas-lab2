class JrcCampaigns::BrokerRecoveryService
  DELAY = 2.minutes
  MAX_ATTEMPTS = 5

  def self.callback_allowed?(payload, token:, callback:, start: false)
    message = Message.find_by(id: payload[:id])
    id = message&.additional_attributes.to_h&.dig('jrc_campaign_broker_delivery_id')
    delivery = JrcCampaigns::Delivery.find_by(id: id, inbox_id: message&.inbox_id)
    return false unless delivery

    new(delivery).callback_allowed?(message, token: token, callback: callback, start: start)
  end

  def self.enqueue_watchdog(id, token, wait_until: nil)
    job = JrcCampaigns::BrokerRecoveryJob.set(wait_until: wait_until || (Time.current + DELAY)).perform_later(id, token)
    raise ActiveJob::EnqueueError, 'Não foi possível agendar a recuperação do envio.' unless job

    job
  end

  def initialize(delivery)
    @delivery = delivery
    @recipient = delivery.recipient
    @campaign = recipient.campaign
  end

  def perform(expected_token)
    action = delivery.with_lock { claim_recovery(expected_token) }
    return unless action

    message, token = action
    if message
      channel = delivery.inbox.channel
      WebhookJob.perform_later(channel.webhook_url, message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook,
                               secret: channel.secret, delivery_id: delivery.metadata.fetch('webhook_delivery_id'), campaign_recovery_token: token)
    else
      JrcCampaigns::DispatchStepService.new(recipient: recipient, step: delivery.step, dispatch_token: token).perform
    end
  end

  def callback_allowed?(message, token:, callback:, start: false)
    delivery.with_lock do
      message.with_lock do
        next false unless valid_callback?(message, token, callback)

        if start
          deferred = JrcCampaigns::BrokerCallbackDeferral.pending?(delivery)
          next false if deferred && !JrcCampaigns::BrokerCallbackDeferral.resume_polling(delivery)

          # Proof and start marker share the message lock. No HTTP runs here.
          JrcBroker::WebhookDiagnostic.new(message).callback_started!
          JrcCampaigns::BrokerCallbackDeferral.clear!(delivery)
        end
        true
      end
    end
  end

  private

  attr_reader :delivery, :recipient, :campaign

  def claim_recovery(expected_token)
    return unless recoverable? && delivery.metadata['dispatch_token'] == expected_token
    return if stop_for_campaign_state?

    message = campaign.account.messages.find_by(id: delivery.metadata['message_id']) if delivery.metadata['message_id']
    return if reconcile_only?(message) || defer_to_window?(expected_token)

    lease_recovery(message)
  end

  def stop_for_campaign_state?
    return false if campaign.reload.running?

    if campaign.paused?
      recipient.update!(metadata: recipient.metadata.to_h.merge('pending_step_id' => delivery.step_id))
      message = campaign.account.messages.find_by(id: delivery.metadata['message_id']) if delivery.metadata['message_id']
      JrcCampaigns::BrokerCallbackDeferral.mark!(delivery, message: message, reason: 'paused') if message
    end
    true
  end

  def reconcile_only?(message)
    return false unless delivery.metadata['message_id'] && (!message || !safe_callback?(message))

    blocked = message && JrcCampaigns::BrokerPreCallbackBlock.new(delivery: delivery, message: message).perform
    JrcCampaigns::BrokerStatusJob.perform_later('campaign', delivery.id) unless blocked
    true
  end

  def defer_to_window?(token)
    target = JrcCampaigns::ScheduleWindow.new(campaign).next_time(Time.current)
    return false unless target.future?

    self.class.enqueue_watchdog(delivery.id, token, wait_until: target)
    true
  end

  def lease_recovery(message)
    attempts = delivery.metadata.fetch('recovery_attempts', 0).to_i
    return exhaust! if attempts >= MAX_ATTEMPTS

    token = SecureRandom.uuid
    # Enqueue before committing the lease so an interrupted owner always has a successor.
    self.class.enqueue_watchdog(delivery.id, token)
    delivery.update!(metadata: delivery.metadata.to_h.merge('dispatch_token' => token, 'recovery_attempts' => attempts + 1))
    [message, token]
  end

  def valid_callback?(message, token, callback)
    return false unless recoverable? && delivery.metadata['dispatch_token'] == token && campaign.reload.running?
    return false unless safe_callback?(message)
    return false if JrcCampaigns::ScheduleWindow.new(campaign).next_time(Time.current).future?

    callback_destination?(callback)
  end

  def callback_destination?(callback)
    channel = delivery.inbox.channel
    channel.webhook_url == callback[:url] && channel.secret.present? && callback[:secret].present? &&
      ActiveSupport::SecurityUtils.secure_compare(channel.secret, callback[:secret]) &&
      delivery.metadata['webhook_delivery_id'] == callback[:delivery_id]
  end

  def recoverable?
    delivery.sending? && delivery.sent_at.nil? && !recipient.reload.status.in?(%w[failed canceled skipped]) &&
      [delivery.inbox.account_id, delivery.inbox_id, delivery.step.campaign_id] == [campaign.account_id, recipient.inbox_id, campaign.id]
  end

  def safe_callback?(message)
    return false unless canonical_message?(message) && safe_proof?(message)
    return false unless JrcCampaigns::ApprovalService.new(campaign.reload).locally_valid?
    return false if replied_follow_up?

    connector = JrcCampaigns::BrokerConnector.for(delivery.inbox.reload)
    return false unless connector && connector.public_configuration == delivery.metadata['broker_connector']

    eligible_recipient?(message)
  end

  def replied_follow_up?
    delivery.step.only_if_no_reply? && recipient.reload.replied_at.present?
  end

  def eligible_recipient?(message)
    contact = message.conversation.contact.reload
    JrcCampaigns::EligibilityPolicy.new(account: campaign.account, phone_number: recipient.phone_number, contact: contact).rejection_reason.nil?
  end

  def canonical_message?(message)
    message_route?(message) && message_authority?(message) && canonical_conversation?(message.conversation.reload)
  end

  def message_route?(message)
    [message.account_id, message.inbox_id, message.id, message.conversation.display_id, delivery.external_id] ==
      [campaign.account_id, delivery.inbox_id, delivery.metadata['message_id'], delivery.metadata['conversation_id'],
       "broker:#{campaign.account_id}:#{delivery.inbox_id}:#{message.id}"]
  end

  def message_authority?(message)
    attrs = message.additional_attributes.to_h
    uuid = delivery.metadata['webhook_delivery_id']
    uuid.present? && [message.message_type, message.private?, message.sender, attrs['jrc_campaign_broker'],
                      attrs['campaign_id'].to_s, attrs['jrc_campaign_broker_delivery_id'], attrs['jrc_campaign_webhook_delivery_id']] ==
      ['outgoing', false, campaign.created_by, true, campaign.id.to_s, delivery.id, uuid]
  end

  def canonical_conversation?(conversation)
    actual = [conversation.account_id, conversation.inbox_id, conversation.contact_id, conversation.contact.account_id, recipient.conversation_id]
    expected = [campaign.account_id, delivery.inbox_id, recipient.contact_id, campaign.account_id, conversation.id]
    actual == expected && canonical_contact_link?(conversation)
  end

  def canonical_contact_link?(conversation)
    link = conversation.contact_inbox
    link && [link.contact_id, link.inbox_id] == [recipient.contact_id, delivery.inbox_id] && link.source_id.present? &&
      JrcCampaigns::PhoneNormalizer.call(conversation.contact.phone_number) == JrcCampaigns::PhoneNormalizer.call(recipient.phone_number)
  end

  def safe_proof?(message)
    JrcBroker::WebhookDiagnostic.pre_callback?(JrcBroker::WebhookDiagnostic.new(message).read)
  end

  def exhaust!
    reason = 'Recuperação automática interrompida após tentativas limitadas. Revise o histórico do envio.'
    delivery.update!(error_message: reason, metadata: delivery.metadata.to_h.merge('recovery_exhausted' => true))
    recipient.update!(error_message: reason, metadata: recipient.metadata.to_h.merge('pending_step_id' => delivery.step_id))
    JrcCampaigns::Campaign.where(id: campaign.id, status: 'running')
                          .update_all(status: 'paused', paused_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    nil
  end
end
