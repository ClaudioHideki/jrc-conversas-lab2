require 'digest'

# Native SendReplyJob uses this guard at the provider boundary for the single published survey instance.
class JrcRelationship::SurveyMessageExecution
  def initialize(message)
    @message = message
  end

  def self.payload_digest(message)
    payload = recipient_payload(message).merge(message_payload(message), attachments: attachment_manifest(message))
    Digest::SHA256.hexdigest(JSON.generate(canonical(payload)))
  end

  def self.recipient_payload(message)
    conversation = message.conversation
    { account_id: message.account_id, conversation_id: message.conversation_id, inbox_id: message.inbox_id,
      contact_id: conversation.contact_id, contact_inbox_id: conversation.contact_inbox_id,
      source_recipient: conversation.contact_inbox.source_id, email_recipient: conversation.contact.email,
      channel_type: message.inbox.channel_type, channel_id: message.inbox.channel_id }
  end

  def self.message_payload(message)
    { content: message.content, content_type: message.content_type, message_type: message.message_type,
      private: message.private?, sender_id: message.sender_id, sender_type: message.sender_type,
      content_attributes: message.content_attributes.to_h.except('external_error'), additional_attributes: message.additional_attributes.to_h }
  end

  def self.attachment_manifest(message)
    message.attachments.order(:id).map do |attachment|
      [attachment.id, attachment.file_type, attachment.file.attached? ? attachment.file.blob.checksum : nil]
    end
  end
  private_class_method :recipient_payload, :message_payload, :attachment_manifest

  def self.canonical(value)
    case value
    when Hash then value.stringify_keys.sort.to_h.transform_values { |child| canonical(child) }
    when Array then value.map { |child| canonical(child) }
    else value
    end
  end

  def self.applies?(message)
    id = message.content_attributes['relationship_survey_id']
    return false if id.blank?

    legacy = JrcRelationship::Survey.find_by(id: id, account_id: message.account_id, source_type: nil)
    legacy.nil? || message.content_attributes['relationship_survey_link'].present?
  end

  def perform
    @survey = JrcRelationship::Survey.find_by(id: @message.content_attributes['relationship_survey_id'], account_id: @message.account_id)
    unless valid_identity?
      @message.update!(status: :failed, external_error: 'Survey dispatch identity invalid')
      return
    end
    return unless claim

    # Recheck revocation after the persisted claim, immediately before channel I/O.
    if (reason = blocker)
      block_dispatch!(reason)
      return
    end
    yield
    self.class.receipt(@message.reload, fallback_unknown: true)
  rescue StandardError
    @survey&.update!(status: 'unknown', failure_code: 'provider_result_unknown', failed_at: Time.current)
    # Unknown external effects must never be retried automatically or leak provider exception text.
  end

  def self.receipt(message, fallback_unknown: false)
    survey = JrcRelationship::Survey.find_by(id: message.content_attributes['relationship_survey_id'], account_id: message.account_id)
    return unless receiptable?(survey, message)

    survey.with_lock do
      state = receipt_state(message, fallback_unknown)
      next unless state
      next if survey.status == 'delivered' && state != 'delivered'

      survey.update!(receipt_attributes(survey, message, state))
      schedule_retry(survey) if state == 'failed'
    end
  end

  def self.receiptable?(survey, message)
    survey && survey.metadata['sent_message_id'] == message.id &&
      %w[queued dispatching sent failed unknown delivered].include?(survey.status)
  end
  private_class_method :receiptable?

  def self.receipt_state(message, fallback_unknown)
    return 'delivered' if %w[delivered read].include?(message.status)
    return 'failed' if message.failed?
    return 'sent' if message.source_id.present?

    'unknown' if fallback_unknown
  end

  def self.receipt_attributes(survey, message, state)
    attrs = { status: state, provider_id: message.source_id }
    attrs[:sent_at] = survey.sent_at || Time.current if %w[sent delivered].include?(state)
    attrs[:delivered_at] = survey.delivered_at || Time.current if state == 'delivered'
    if %w[failed unknown].include?(state)
      attrs[:failed_at] = Time.current
      attrs[:failure_code] = state == 'unknown' ? 'provider_result_unverified' : 'provider_failure'
    end
    attrs
  end

  def self.schedule_retry(survey)
    return unless survey.attempts < survey.rule_snapshot.dig('settings', 'max_attempts').to_i && survey.expires_at > Time.current
    return if survey.metadata['retry_scheduled_attempt'] == survey.attempts

    survey.update!(metadata: survey.metadata.merge('retry_scheduled_attempt' => survey.attempts))
    JrcRelationship::SurveyDispatchJob.set(wait: survey.rule_snapshot.dig('settings', 'resend_minutes').to_i.minutes).perform_later(survey.id)
  end
  private_class_method :receipt_state, :receipt_attributes, :schedule_retry

  private

  def valid_identity?
    @survey && (@survey.source_type.present? || @message.additional_attributes['template_params'].present?) &&
      @survey.metadata['sent_message_id'] == @message.id
  end

  def claim
    @survey.with_lock do
      next false unless @survey.status == 'queued'

      reason = blocker
      if reason
        block_dispatch!(reason)
        next false
      end
      @survey.update!(status: 'dispatching', dispatch_started_at: Time.current)
      true
    end
  end

  def block_dispatch!(reason)
    @survey.update!(status: 'blocked', failure_code: reason)
    @message.update!(status: :failed, external_error: 'Survey dispatch blocked by current policy')
  end

  def blocker
    return manual_template_blocker if @survey.source_type.blank?

    execution = JrcRelationship::SurveyExecutionContext.new(@survey)
    reason = execution.blocker
    return reason if reason

    allowed = execution.conversation
    return 'channel_access_revoked' unless authorized_channel?(execution, allowed)
    return 'message_payload_changed' unless @survey.metadata['message_payload_digest'] == self.class.payload_digest(@message)
    return 'incompatible_delivery_control' if incompatible_delivery_control?

    nil
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    'source_access_denied'
  end

  def incompatible_delivery_control?
    %w[service_desk_delivery_id jrc_flow_run_id nico_delegation].any? do |key|
      @message.content_attributes[key].present?
    end
  end

  def manual_template_blocker
    member = AccountUser.find_by!(account_id: @survey.account_id, user_id: @survey.metadata['sent_by_id'])
    context = JrcRelationship::Context.new(member)
    assignment = context.assignment(@survey.assignment_id, write: true)
    allowed = assignment.customer_context(member).conversations.find(@message.conversation_id)
    return 'channel_access_revoked' unless ConversationPolicy.new(context.to_h, allowed).show?
    return 'message_payload_changed' unless @survey.metadata['message_payload_digest'] == self.class.payload_digest(@message)
    return 'template_access_revoked' unless JrcRelationship::SurveyWhatsappTemplate.valid_message?(@survey, @message)
    return 'survey_expired' if @survey.responded_at || @survey.expires_at <= Time.current

    nil
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    'source_access_denied'
  end

  def authorized_channel?(execution, allowed)
    return false unless allowed&.id == @message.conversation_id && ConversationPolicy.new(execution.context.to_h, allowed).show?

    sealed_link = @message.content_attributes['relationship_survey_link']
    sealed_link.present? ? JrcRelationship::SurveyWhatsappTemplate.valid_message?(@survey, @message) : allowed.can_reply?
  end
end
