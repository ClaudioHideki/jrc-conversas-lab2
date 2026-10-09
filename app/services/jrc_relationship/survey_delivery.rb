class JrcRelationship::SurveyDelivery
  def initialize(context:, survey:, base_url:)
    @context = context
    @survey = survey
    @base_url = base_url.to_s.delete_suffix('/')
  end

  def call(conversation_id:, template_params: nil, content: nil, configured_template: false)
    @template_params = template_params
    @template_content = content
    delivery = authorized_delivery(conversation_id)
    conversation = delivery[:conversation]
    raise Pundit::NotAuthorizedError unless ConversationPolicy.new(@context.to_h, conversation).show?

    apply_configured_template(conversation) if configured_template
    validate_channel!(conversation)
    @survey.with_lock { deliver_locked(conversation, conversation.inbox.channel_type, delivery[:source]) }
  end

  private

  def apply_configured_template(conversation)
    configured = JrcRelationship::SurveyRuleTemplate.delivery(@survey, conversation, survey_url)
    return unless configured

    @template_params = configured[:template_params]
    @template_content = configured[:content]
    @template_revision = configured[:revision]
  end

  def authorized_delivery(conversation_id)
    if @survey.source_type.present?
      execution = JrcRelationship::SurveyExecutionContext.new(@survey)
      raise Pundit::NotAuthorizedError if execution.blocker || @survey.execution_member_id != @context.member.id

      source = execution.origin.source
      allowed = execution.conversation
      raise Pundit::NotAuthorizedError unless allowed && allowed.id == conversation_id.to_i

      { conversation: allowed, source: source }
    else
      @context.assignment(@survey.assignment_id, write: true)
      { conversation: @survey.assignment.customer_context(@context.member).conversations.find(conversation_id), source: nil }
    end
  end

  def validate_channel!(conversation)
    channel = conversation.inbox.channel_type
    raise ArgumentError, 'Select an existing WhatsApp or e-mail conversation' unless whatsapp_channel?(conversation,
                                                                                                       channel) || channel == 'Channel::Email'
    return validate_template!(conversation) if @template_params.present?

    raise ArgumentError, 'The selected conversation cannot receive replies now' unless conversation.can_reply?
  end

  def whatsapp_channel?(conversation, channel)
    channel == 'Channel::Whatsapp' || (channel == 'Channel::TwilioSms' && conversation.inbox.twilio_whatsapp?)
  end

  def validate_template!(conversation)
    raise ArgumentError, 'Template preview is required' unless @template_content.is_a?(String) && @template_content.length.between?(1, 16_000)

    JrcRelationship::SurveyWhatsappTemplate.new(survey: @survey, conversation: conversation, url: survey_url, origin: @base_url,
                                                params: @template_params).validate!
  end

  def deliver_locked(conversation, channel, source)
    raise ArgumentError, 'Survey expired or already answered' if @survey.responded_at || @survey.expires_at <= Time.current

    previous = previous_message(conversation)
    return previous if previous

    return build_native_csat(conversation, channel) if @template_params.blank? && native_csat?(source)

    message = Messages::MessageBuilder.new(@context.user, conversation, link_message_params(conversation, channel)).perform
    record_message!(message, channel)
    @context.audit!(@survey, after: { message_id: message.id, channel: channel },
                             action: @survey.source_type.present? ? 'survey_queued' : 'survey_sent')
    message
  end

  def previous_message(conversation)
    previous_id = @survey.metadata['sent_message_id']
    return unless previous_id

    previous = @context.account.messages.find(previous_id)
    validate_replay!(previous, conversation) if @template_params.present?
    if retry_failed_message?(previous)
      @survey.metadata = @survey.metadata.except('sent_message_id', 'message_payload_digest').merge(
        'message_attempt_ids' => (Array(@survey.metadata['message_attempt_ids']) + [previous.id]).uniq
      )
      return
    end
    @survey.update!(status: 'delivered', delivered_at: Time.current) if %w[delivered read].include?(previous.status) && @survey.status != 'delivered'
    previous
  end

  def validate_replay!(previous, conversation)
    matches = previous.conversation_id == conversation.id && previous.content == @template_content &&
              previous.additional_attributes['template_params'] == @template_params
    raise ArgumentError, 'The existing survey message has a different template delivery intent' unless matches
  end

  def retry_failed_message?(previous)
    @survey.source_type && previous.failed? && @survey.attempts <= @survey.rule_snapshot.dig('settings', 'max_attempts').to_i
  end

  def native_csat?(source)
    first = @survey.questions.first
    @survey.kind == 'csat' && source.is_a?(Conversation) && @survey.questions.size == 1 &&
      first['type'] == 'scale' && first['min'] == 1 && first['max'] == 5
  end

  def build_native_csat(conversation, channel)
    inputs = conversation.messages.where(content_type: :input_csat).where.not(id: Array(@survey.metadata['message_attempt_ids']))
    raise ArgumentError, 'Native CSAT already exists for this conversation' if inputs.exists?
    raise ArgumentError, 'Native CSAT requires an enabled inbox' unless conversation.inbox.csat_survey_enabled?

    params = { content: @survey.questions.first['text'], message_type: 'outgoing', content_type: 'input_csat',
               content_attributes: { relationship_survey_id: @survey.id,
                                     display_type: conversation.inbox.csat_config&.dig('display_type') || 'emoji' } }
    message = Messages::MessageBuilder.new(@context.user, conversation, params).perform
    record_message!(message, channel)
    message
  end

  def link_message_params(conversation, channel)
    params = { content: link_content, message_type: 'outgoing',
               content_attributes: { relationship_survey_id: @survey.id } }
    if @template_params.present?
      params[:template_params] = @template_params
      params[:content_attributes].merge!(relationship_survey_link: survey_url, relationship_survey_link_origin: @base_url)
      params[:content_attributes][:relationship_survey_template_revision] = @template_revision if @template_revision
    end
    if channel == 'Channel::Email'
      raise ArgumentError, 'The customer has no e-mail address' if conversation.contact.email.blank?

      params[:to_emails] = conversation.contact.email
    end
    params
  end

  def link_content
    @template_content || "Pesquisa #{@survey.kind.upcase}: #{@survey.metadata['question']}\n#{survey_url}"
  end

  def survey_url
    "#{@base_url}/jrc/relacionamento/pesquisas/#{@survey.signed_id(purpose: :relationship_survey)}"
  end

  def record_message!(message, channel)
    queued = @survey.source_type.present? || @template_params.present?
    attrs = { status: queued ? 'queued' : 'sent', metadata: message_metadata(message, channel) }
    attrs[:sent_at] = Time.current unless queued
    @survey.update!(attrs)
  end

  def message_metadata(message, channel)
    @survey.metadata.merge('sent_message_id' => message.id, 'sent_conversation_id' => message.conversation_id,
                           'survey_link_url' => survey_url, 'survey_link_origin' => @base_url,
                           'sent_channel' => channel, 'queued_at' => Time.current.iso8601, 'sent_by_id' => @context.user.id,
                           'message_payload_digest' => JrcRelationship::SurveyMessageExecution.payload_digest(message))
  end
end
