require 'digest'

class Whatsapp::RetryPolicy
  VERSION = 'cloud-template-manual-v2'.freeze
  TRANSIENT_CODES = %w[130429 131016].freeze
  MANUAL_RETRY_CODES = (TRANSIENT_CODES + %w[130472]).freeze

  def self.error_code(message)
    message.external_error.to_s[/\A\s*(\d{6})(?=\s*:|\s*\z)/, 1]
  end

  def self.allowed_actor?(message, actor)
    return false unless actor.is_a?(User)

    member = AccountUser.find_by(account_id: message.account_id, user_id: actor.id)
    member.present? && ConversationPolicy.new({ user: actor, account: message.account, account_user: member }, message.conversation).show?
  end

  def self.reason(message, actor, cooldown: true)
    code = error_code(message)
    return 'marketing_restriction' if code == '131049'
    return 'destination_verification_required' if code == '131026'

    channel = message.inbox.channel
    return 'retry_unavailable' unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
    return 'retry_unavailable' unless message.failed? && message.outgoing? && message.content_type == 'text' && message.source_id.present? && !message.private?
    return 'retry_unavailable' unless MANUAL_RETRY_CODES.include?(code) && allowed_actor?(message, actor)
    return 'retry_unavailable' if cooldown && message.updated_at > 60.seconds.ago
    return 'retry_unavailable' unless message.sender_type == 'User' && message.attachments.empty?
    return 'retry_unavailable' if message.content_attributes.except('external_error', 'in_reply_to', 'in_reply_to_external_id').present?
    return 'retry_unavailable' if message.additional_attributes.to_h.except('template_params').present?
    return 'retry_unavailable' unless valid_template?(message.additional_attributes.to_h['template_params'], channel.message_templates)

    nil
  end

  # Conservative text-template subset. Reject unsupported media/buttons rather than dropping parameters.
  def self.valid_template?(params, templates)
    return false unless params.is_a?(Hash) && params.values_at('name', 'language', 'category').all?(&:present?)

    template = Array(templates).find do |item|
      item['name'] == params['name'] && item['language'] == params['language'] && item['status'].to_s.casecmp?('approved') &&
        item['category'].to_s.casecmp?(params['category'].to_s)
    end
    return false unless template && template['components'].is_a?(Array)
    return false unless template['components'].all? { |component| supported_component?(component) }

    body = template['components'].find { |component| component['type'] == 'BODY' }
    return false unless body && body['text'].is_a?(String)
    return false if template['components'].any? { |component| component['type'] == 'FOOTER' && component['text'].to_s.include?('{{') }

    processed = params['processed_params']
    return false unless processed.is_a?(Hash) && (processed.keys - ['body']).empty?

    values = processed.fetch('body', {})
    placeholders = body['text'].scan(/\{\{([^{}]+)\}\}/).flatten.uniq.sort
    return false unless template['parameter_format'] == 'NAMED' || placeholders.sort_by(&:to_i) == (1..placeholders.size).map(&:to_s)

    values.is_a?(Hash) && values.keys.sort == placeholders && values.values.all? { |value| value.is_a?(String) && value.present? }
  end

  def self.supported_component?(component)
    return true if %w[BODY FOOTER].include?(component['type'])

    component['type'] == 'HEADER' && component['format'] == 'TEXT' &&
      component['text'].is_a?(String) && component['text'].present? && component['text'].exclude?('{{')
  end
  private_class_method :supported_component?

  def self.fingerprint(message)
    channel = message.inbox.channel
    Digest::SHA256.hexdigest([
      message.source_id, message.content, message.content_attributes.to_json, message.additional_attributes.to_json,
      message.conversation.contact_inbox.source_id, channel.provider,
      channel.provider_config.values_at('api_key', 'phone_number_id', 'business_account_id')
    ].to_json)
  end
end
