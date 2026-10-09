require 'digest'

# Shared validation around the official parser/provider payload, never a second parser.
class JrcRelationship::SurveyTemplateSelection
  def initialize(account_id:, inbox:, params:)
    @account_id = account_id
    @inbox = inbox
    @params = params
  end

  def validate!
    raise ArgumentError, 'Select an approved template for the current WhatsApp inbox' unless approved_template
    raise ArgumentError, 'Survey template parameters are invalid' unless valid_params?

    approved_template
  end

  def fingerprint
    validate!
    channel = @inbox.channel
    source = { template: approved_template, account_id: @account_id, inbox_id: @inbox.id, channel_id: channel.id,
               provider: channel.provider, phone_number: channel.phone_number,
               provider_identity: channel.provider_config.slice('business_account_id', 'phone_number_id') }
    Digest::SHA256.hexdigest(JSON.generate(JrcRelationship::SurveyMessageExecution.canonical(source)))
  end

  def body_texts
    validate!
    native = Whatsapp::TemplateProcessorService.new(channel: @inbox.channel, template_params: @params.deep_dup).call.last
    Array(native).select { |item| item[:type] == 'body' }.flat_map { |item| item[:parameters] }.pluck(:text)
  end

  private

  def approved_template
    return unless @inbox.account_id == @account_id && @inbox.channel_type == 'Channel::Whatsapp'
    return unless @params.is_a?(Hash) && @params['name'].is_a?(String) && @params['language'].is_a?(String)

    @approved_template ||= Array(@inbox.channel.message_templates).find do |template|
      template['status'].to_s.downcase == 'approved' &&
        template.values_at('name', 'language', 'category') == @params.values_at('name', 'language', 'category') &&
        template['namespace'].to_s == @params['namespace'].to_s
    end
  end

  def valid_params?
    return false unless @params.to_json.bytesize <= 32_000 && (@params.keys - %w[name language category namespace processed_params]).empty?

    parts = @params['processed_params']
    return false unless JrcRelationship::SurveyTemplateParameters.valid?(parts)

    body = parts['body']
    body.is_a?(Hash) && body.size <= 20 && body.keys.sort == body_keys.sort &&
      body.values.all? { |value| value.is_a?(String) && value.length.between?(1, 4000) }
  end

  def body_keys
    body = approved_template.fetch('components', []).find { |item| item['type']&.upcase == 'BODY' }
    body&.fetch('text', '').to_s.scan(/\{\{\s*(\w+)\s*\}\}/).flatten.uniq
  end
end
