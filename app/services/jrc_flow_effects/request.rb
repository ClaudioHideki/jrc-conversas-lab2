require 'digest'

class JrcFlowEffects::Request
  PROTOCOL = 'jrc-conversation-effects/2'.freeze
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
  SHA = /\A[0-9a-f]{64}\z/
  MAX_SAFE_INTEGER = 9_007_199_254_740_991
  KEYS = %w[organization_id operation_id dispatch_proof inbox_id remote_contact_id expected_control_revision operation
            resource_id resource_revision value_json integration_id].freeze

  def self.integer(value, zero: false)
    pattern = zero ? /\A(?:0|[1-9][0-9]*)\z/ : /\A[1-9][0-9]*\z/
    raise ArgumentError, 'id' unless pattern.match?(value.to_s) && value.to_s.length <= 16 && value.to_i <= MAX_SAFE_INTEGER

    value.to_i
  end

  def self.validate(input)
    raise ArgumentError, 'identity' unless %w[organization_id operation_id dispatch_proof].all? { |key| UUID.match?(input[key].to_s) }
    raise ArgumentError, 'operation' unless %w[tag attribute note resolve domain].include?(input['operation'])

    validate_scope(input)
    validate_resource(input)
    return JrcDomainCommands::Request.parse(input['value_json']) if input['operation'] == 'domain'

    scalar(input['value_json'])
  end

  def self.validate_scope(input)
    %w[inbox_id remote_contact_id expected_control_revision].each do |key|
      raise ArgumentError, 'id' unless input[key].is_a?(String)
    end
    %w[inbox_id remote_contact_id].each { |key| integer(input[key]) }
    integer(input['expected_control_revision'], zero: true)
  end

  def self.validate_resource(input)
    if %w[tag attribute].include?(input['operation'])
      raise ArgumentError, 'id' unless input['resource_id'].is_a?(String)

      integer(input['resource_id'])
      raise ArgumentError, 'resource_revision' unless SHA.match?(input['resource_revision'].to_s)
    elsif input['resource_id'].present? || input['resource_revision'].present?
      raise ArgumentError, 'resource'
    end
  end

  def self.scalar(raw)
    raise ArgumentError, 'value' unless raw.is_a?(String) && raw.valid_encoding? && raw.bytesize <= 8192

    value = JSON.parse(raw)
    raise ArgumentError, 'value' unless scalar_value?(value)

    value
  rescue JSON::ParserError
    raise ArgumentError, 'value'
  end

  def self.scalar_value?(value)
    !value.is_a?(Array) && !value.is_a?(Hash) && (!value.is_a?(Numeric) || value.finite?)
  end

  def self.digest(input, account_id:, conversation_id:)
    material = [
      PROTOCOL, input.fetch('organization_id'), input.fetch('operation_id'), account_id.to_s,
      input.fetch('inbox_id').to_s, conversation_id.to_s, input.fetch('remote_contact_id').to_s,
      input.fetch('expected_control_revision').to_s, input.fetch('operation'), input['resource_id'].to_s,
      input['resource_revision'].to_s, Digest::SHA256.hexdigest(input.fetch('value_json'))
    ]
    material << input.fetch('integration_id') if input['operation'] == 'domain'
    Digest::SHA256.hexdigest(material.join("\n"))
  end
end
