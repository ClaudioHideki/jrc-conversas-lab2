require 'time'

class JrcDomainCommands::Request
  COMMANDS = %w[create_lead create_task create_meeting].freeze
  PROTOCOL = 'jrc-domain-commands/1'.freeze

  def self.available?
    JrcFlowEffects::ControlRevision.available? && JrcFlowEffectReceipt.column_names.include?('domain_result')
  end

  def self.parse(raw)
    value = decode(raw)
    raise ArgumentError, 'domain_command' unless value.is_a?(Hash) && COMMANDS.include?(value['command'])

    keys = value['command'] == 'create_lead' ? ['command'] : %w[command title due_at owner_id]
    raise ArgumentError, 'domain_keys' unless value.keys.sort == keys.sort

    validate_activity(value) unless value['command'] == 'create_lead'
    value
  end

  def self.decode(raw)
    raise ArgumentError, 'domain_payload' unless raw.is_a?(String) && raw.bytesize <= 8192

    JSON.parse(raw, max_nesting: 8)
  rescue JSON::ParserError
    raise ArgumentError, 'domain_payload'
  end

  def self.validate_activity(value)
    valid = valid_title?(value['title']) && valid_owner?(value['owner_id']) &&
            value['due_at'].is_a?(String) && value['due_at'].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})\z/)
    raise ArgumentError, 'domain_activity' unless valid

    Time.iso8601(value.fetch('due_at'))
  end

  def self.valid_title?(title)
    title.is_a?(String) && title.strip.present? && title.bytesize <= 200
  end

  def self.valid_owner?(owner)
    owner.is_a?(Integer) && owner.between?(1, JrcFlowEffects::Request::MAX_SAFE_INTEGER)
  end
end
