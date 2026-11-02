# frozen_string_literal: true

# Uses the cached approved template and the application's native WhatsApp parser.
# This class never fetches, approves or sends a provider template.
class JrcServiceDesk::NotificationWhatsappTemplate
  def self.choices(inbox)
    return [] unless inbox.channel_type == 'Channel::Whatsapp'

    Array(inbox.channel.message_templates).filter_map do |template|
      next unless template['status'].to_s.downcase == 'approved'

      components = Array(template['components'])
      body = components.find { |part| part['type'].to_s.upcase == 'BODY' }&.fetch('text', nil)
      next unless body.is_a?(String) && body.length.between?(1, 10_000)
      next if components.any? { |part| unsupported_component?(part) }

      keys = body.scan(/\{\{\s*(\w+)\s*\}\}/).flatten.uniq
      next if keys.size > 20

      params = template.slice('name', 'language', 'category', 'namespace').merge('processed_params' => {
                                                                                   'body' => keys.index_with { '{{number}}' }
                                                                                 })
      selection = JrcRelationship::SurveyTemplateSelection.new(account_id: inbox.account_id, inbox: inbox, params: params)
      { 'inbox_id' => inbox.id.to_s, 'params' => params, 'fingerprint' => selection.fingerprint, 'text' => body }
    rescue ArgumentError, KeyError
      nil
    end
  end

  def self.unsupported_component?(part)
    type = part['type'].to_s.upcase
    return false if type == 'BODY'
    return true if type == 'HEADER' && part['format'].to_s.upcase != 'TEXT'

    part.to_json.include?('{{')
  end

  def initialize(inbox:, configuration:)
    @inbox = inbox
    @configuration = JrcServiceDesk::Input.attributes(configuration, %w[inbox_id params fingerprint])
  end

  def validate!
    raise ArgumentError, 'Template inbox changed' unless @configuration['inbox_id'].to_s == @inbox.id.to_s
    raise ArgumentError, 'Template identity required' unless @configuration['fingerprint'].is_a?(String)

    params = @configuration.fetch('params')
    raise ArgumentError unless params.is_a?(Hash) && params['processed_params'].is_a?(Hash) && params['processed_params'].keys == ['body']

    selection = JrcRelationship::SurveyTemplateSelection.new(account_id: @inbox.account_id, inbox: @inbox, params: params)
    @native = selection.validate!
    raise ArgumentError, 'Template changed or no longer approved' unless selection.fingerprint == @configuration['fingerprint']
    raise ArgumentError unless Array(@native['components']).none? { |part| self.class.unsupported_component?(part) }

    values = params.fetch('processed_params').fetch('body').values
    raise ArgumentError unless values.all? { |value| (value.scan(/\{\{(.*?)\}\}/).flatten - JrcServiceDesk::NotificationSource::FIELDS).empty? }

    self
  end

  def message_parameters(fields)
    validate!
    params = @configuration.fetch('params').deep_dup
    body = params.fetch('processed_params').fetch('body')
    body.transform_values! { |value| JrcServiceDesk::NotificationSource.render(value, fields) }
    raise ArgumentError, 'Empty template parameter' unless body.values.all? { |value| value.length.between?(1, 4000) }

    # Run the same parser used by SendOnWhatsappService before persisting a message.
    JrcRelationship::SurveyTemplateSelection.new(account_id: @inbox.account_id, inbox: @inbox, params: params).body_texts
    text = Array(@native['components']).find { |part| part['type'].to_s.upcase == 'BODY' }.fetch('text')
    content = text.gsub(/\{\{\s*(\w+)\s*\}\}/) { body.fetch(Regexp.last_match(1)) }
    { content: content, template_params: params }
  end
end
