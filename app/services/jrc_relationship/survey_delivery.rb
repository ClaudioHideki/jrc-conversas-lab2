class JrcRelationship::SurveyDelivery
  def initialize(context:, survey:, base_url:)
    @context, @survey, @base_url = context, survey, base_url.to_s.delete_suffix('/')
  end

  def call(conversation_id:)
    @context.assignment(@survey.assignment_id, write: true)
    conversation = @survey.assignment.customer_context(@context.member).conversations.find(conversation_id)
    raise Pundit::NotAuthorizedError unless ConversationPolicy.new(@context.to_h, conversation).show?
    channel = conversation.inbox.channel_type
    whatsapp = channel == 'Channel::Whatsapp' || (channel == 'Channel::TwilioSms' && conversation.inbox.twilio_whatsapp?)
    raise ArgumentError, 'Select an existing WhatsApp or e-mail conversation' unless whatsapp || channel == 'Channel::Email'
    raise ArgumentError, 'The selected conversation cannot receive replies now' unless conversation.can_reply?
    @survey.with_lock do
      raise ArgumentError, 'Survey expired or already answered' if @survey.responded_at || @survey.expires_at <= Time.current
      previous_id = @survey.metadata['sent_message_id']
      return @context.account.messages.find(previous_id) if previous_id
      url = "#{@base_url}/jrc/relacionamento/pesquisas/#{@survey.signed_id(purpose: :relationship_survey)}"
      params = { content: "Pesquisa #{@survey.kind.upcase}: #{url}", message_type: 'outgoing',
        content_attributes: { relationship_survey_id: @survey.id } }
      if channel == 'Channel::Email'
        raise ArgumentError, 'The customer has no e-mail address' if conversation.contact.email.blank?
        params[:to_emails] = conversation.contact.email
      end
      message = Messages::MessageBuilder.new(@context.user, conversation, params).perform
      @survey.update!(metadata: @survey.metadata.merge('sent_message_id' => message.id, 'sent_conversation_id' => conversation.id,
        'sent_channel' => channel, 'sent_at' => Time.current.iso8601, 'sent_by_id' => @context.user.id))
      @context.audit!(@survey, after: { message_id: message.id, channel: channel }, action: 'survey_sent')
      message
    end
  end
end
