# Versioned configuration for the existing native survey delivery path.
class JrcRelationship::SurveyRuleTemplate
  LINK_MARKER = '{{survey_url}}'.freeze
  KEYS = %w[inbox_id content template_params template_fingerprint].freeze

  def initialize(rule)
    @rule = rule
    @configuration = rule.effective_settings['whatsapp_template']
  end

  def normalize!
    return if @configuration.nil?

    validate_configuration!
    fingerprint = selection.fingerprint
    previous = @configuration['template_fingerprint']
    raise ArgumentError, 'The approved template changed; select it again' if previous.present? && previous != fingerprint

    @rule.settings = @rule.settings.merge('whatsapp_template' => @configuration.merge('template_fingerprint' => fingerprint))
  end

  def validate!
    return if @configuration.nil?

    validate_configuration!
    raise ArgumentError, 'The approved template changed; select it again' unless @configuration['template_fingerprint'] == selection.fingerprint
  end

  def self.delivery(survey, conversation, url)
    config = survey.rule_snapshot.dig('settings', 'whatsapp_template')
    return if config.nil?

    rule = survey.rule.reload
    new(rule).validate!
    raise ArgumentError, 'Survey template configuration changed' unless config == rule.effective_settings['whatsapp_template']
    raise ArgumentError, 'Survey template inbox changed' unless config['inbox_id'].to_s == conversation.inbox_id.to_s

    params = config.fetch('template_params').deep_dup
    params['processed_params'] = substitute(params.fetch('processed_params'), url)
    { template_params: params, content: substitute(config.fetch('content'), url),
      revision: config.fetch('template_fingerprint') }
  end

  def self.valid_message?(survey, message)
    revision = message.content_attributes['relationship_survey_template_revision']
    return true if revision.nil?

    expected = delivery(survey, message.conversation, survey.metadata.fetch('survey_link_url'))
    expected && expected[:revision] == revision && expected[:template_params] == message.additional_attributes['template_params'] &&
      expected[:content] == message.content
  rescue ArgumentError, KeyError, Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    false
  end

  def self.substitute(value, url)
    case value
    when Hash then value.transform_values { |child| substitute(child, url) }
    when Array then value.map { |child| substitute(child, url) }
    when String then value.gsub(LINK_MARKER, url)
    else value
    end
  end
  private_class_method :substitute

  private

  def validate_configuration!
    config = @configuration
    raise ArgumentError, 'Invalid survey template configuration' unless config.is_a?(Hash) && (config.keys - KEYS).empty?
    raise ArgumentError, 'Select an explicit WhatsApp delivery inbox' unless @rule.effective_settings['channel'] == 'whatsapp' &&
                                                                         config['inbox_id'].to_s == @rule.effective_settings['delivery_inbox_id'].to_s
    raise ArgumentError, 'Template preview must contain the survey link marker' unless config['content'].is_a?(String) &&
                                                                                    config['content'].length.between?(1, 16_000) &&
                                                                                    config['content'].include?(LINK_MARKER)

    authorize_executor!
    raise ArgumentError, 'A body parameter must contain the survey link marker' unless selection.body_texts.any? do |text|
      text.to_s.include?(LINK_MARKER)
    end
  end

  def authorize_executor!
    member = @rule.execution_member
    raise ArgumentError, 'Select an explicit survey execution member' unless member && member.account_id == @rule.account_id

    context = JrcRelationship::Context.new(member)
    allowed = context.policy.manage? && (member.administrator? || InboxMember.exists?(inbox_id: inbox.id, user_id: member.user_id))
    raise Pundit::NotAuthorizedError unless allowed
  end

  def inbox
    @inbox ||= Inbox.where(account_id: @rule.account_id).find(@configuration['inbox_id'])
  end

  def selection
    @selection ||= JrcRelationship::SurveyTemplateSelection.new(account_id: @rule.account_id, inbox: inbox,
                                                                params: @configuration['template_params'])
  end
end
