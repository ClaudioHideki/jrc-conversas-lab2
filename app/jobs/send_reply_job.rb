class SendReplyJob < ApplicationJob
  queue_as :high

  CHANNEL_SERVICES = {
    'Channel::TwitterProfile' => ::Twitter::SendOnTwitterService,
    'Channel::TwilioSms' => ::Twilio::SendOnTwilioService,
    'Channel::Line' => ::Line::SendOnLineService,
    'Channel::Telegram' => ::Telegram::SendOnTelegramService,
    'Channel::Whatsapp' => ::Whatsapp::SendOnWhatsappService,
    'Channel::Sms' => ::Sms::SendOnSmsService,
    'Channel::Instagram' => ::Instagram::SendOnInstagramService,
    'Channel::Tiktok' => ::Tiktok::SendOnTiktokService,
    'Channel::Email' => ::Email::SendOnEmailService,
    'Channel::WebWidget' => ::Messages::SendEmailNotificationService,
    'Channel::Api' => ::Messages::SendEmailNotificationService
  }.freeze

  def perform(message_id)
    message = Message.find(message_id)
    if message.content_attributes.to_h['service_desk_delivery_id']
      JrcServiceDesk::NotificationExecution.new(message).perform { deliver(message) }
    elsif JrcRelationship::SurveyMessageExecution.applies?(message)
      JrcRelationship::SurveyMessageExecution.new(message).perform { deliver(message) }
    elsif message.content_attributes.to_h['jrc_flow_run_id']
      JrcFlows::Delivery.new(message).perform { deliver(message) }
    elsif message.content_attributes.to_h['nico_delegation']
      deliver_nico(message)
    else
      deliver(message)
    end
  end

  def deliver(message)
    channel_name = message.conversation.inbox.channel.class.to_s

    return send_on_facebook_page(message) if channel_name == 'Channel::FacebookPage'

    service_class = CHANNEL_SERVICES[channel_name]
    return unless service_class

    service_class.new(message: message).perform
  end

  private

  def deliver_nico(message)
    turn = JrcNico::Turn.find_by(id: message.content_attributes['nico_turn_id'], outgoing_message_id: message.id)
    claimed = message.conversation.with_lock do
      unless JrcNico::DelegationService.delivery_allowed?(message)
        message.update!(status: :failed, content_attributes: message.content_attributes.merge('external_error' => 'NICO: atendimento retomado ou autorização expirada.'))
        turn&.update!(status: 'cancelled')
        next false
      end
      next false unless turn&.reload&.status == 'queued'

      turn.update!(status: 'dispatching')
      true
    end
    return unless claimed

    # Commit dispatching before channel I/O: an uncertain delivery must not be sent twice on job retry.
    message.conversation.with_lock do
      unless JrcNico::DelegationService.delivery_allowed?(message)
        message.update!(status: :failed)
        turn.update!(status: 'cancelled')
        next
      end
      deliver(message)
      turn.update!(status: message.reload.failed? ? 'failed' : 'channel_processed')
      if message.failed?
        JrcNico::DelegationService.stop(message.conversation, reason: 'delivery_failed', status: 'needs_human')
      end
    end
  rescue StandardError
    turn&.update!(status: 'unknown')
    JrcNico::DelegationService.stop(message.conversation, reason: 'delivery_unknown', status: 'needs_human')
  end

  def send_on_facebook_page(message)
    if message.conversation.additional_attributes['type'] == 'instagram_direct_message'
      ::Instagram::Messenger::SendOnInstagramService.new(message: message).perform
    else
      ::Facebook::SendOnFacebookService.new(message: message).perform
    end
  end
end
