require 'digest'
require 'json'

module JrcBroker::LiveIngressContract
  PROTOCOL = 'jrc-live-ingress/1'.freeze
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
  HASH = /\A[a-f0-9]{64}\z/
  MAX_MEDIA_BYTES = 16.megabytes
  MAX_PENDING_BYTES = 64.megabytes
  SCOPE_KEYS = %w[protocol organization_id integration_id instance_id destination_revision].freeze
  MESSAGE_KEYS = (SCOPE_KEYS + %w[broker_message_id conversation_id message_type message_origin content media request_hash]).freeze
  MEDIA_KEYS = %w[filename mime_type byte_size sha256].freeze

  def validate_keys!(input, keys)
    raise ArgumentError, 'JRC_LIVE_INPUT' unless input.is_a?(Hash) && input.keys.sort == keys.sort
  end

  def validate_scope!(input)
    valid = input['protocol'] == PROTOCOL && %w[organization_id integration_id instance_id].all? { |key| UUID.match?(input[key].to_s) } &&
            positive_integer?(input['destination_revision'])
    raise ArgumentError, 'JRC_LIVE_SCOPE' unless valid
  end

  def validate_message!(input)
    validate_keys!(input, message_keys(input))
    validate_scope!(input)
    validate_clock!(input)
    valid = UUID.match?(input['broker_message_id'].to_s) && positive_integer?(input['conversation_id']) &&
            valid_direction?(input) && valid_content?(input) && HASH.match?(input['request_hash'].to_s)
    raise ArgumentError, 'JRC_LIVE_INPUT' unless valid

    digest = Digest::SHA256.hexdigest(JSON.generate(canonical(input.except('request_hash'))))
    raise ArgumentError, 'JRC_LIVE_HASH' unless digest == input['request_hash']
  end

  def message_keys(input)
    input.is_a?(Hash) && input.key?('occurred_at') ? MESSAGE_KEYS + ['occurred_at'] : MESSAGE_KEYS
  end

  def validate_clock!(input)
    return unless input.key?('occurred_at')

    value = input['occurred_at']
    valid = value.is_a?(Integer) && value.between?(0, [Time.current.to_i + 300, 9_007_199_254_740_991].min)
    raise ArgumentError, 'JRC_LIVE_CLOCK' unless valid
  end

  def valid_direction?(input)
    %w[incoming outgoing].include?(input['message_type']) && %w[LIVE EXTERNAL_OBSERVED].include?(input['message_origin']) &&
      (input['message_origin'] != 'EXTERNAL_OBSERVED' || input['message_type'] == 'outgoing')
  end

  def valid_content?(input)
    input['content'].is_a?(String) && input['content'].valid_encoding? && input['content'].bytesize <= 65_536 &&
      (input['media'].nil? ? !input['content'].empty? : valid_media?(input['media']))
  end

  def positive_integer?(value)
    value.is_a?(Integer) && value.between?(1, 9_007_199_254_740_991)
  end

  def canonical(value)
    return value.keys.sort.index_with { |key| canonical(value.fetch(key)) } if value.is_a?(Hash)
    return value.map { |entry| canonical(entry) } if value.is_a?(Array)

    value
  end

  def valid_media?(value)
    value.is_a?(Hash) && value.keys.sort == MEDIA_KEYS.sort && valid_filename?(value['filename']) && valid_mime?(value['mime_type']) &&
      value['byte_size'].is_a?(Integer) && value['byte_size'].between?(1, MAX_MEDIA_BYTES) &&
      HASH.match?(value['sha256'].to_s)
  end

  def valid_filename?(value)
    value.is_a?(String) && value.bytesize.between?(1, 255) && !%r{[\x00-\x1f\x7f/\\]}.match?(value)
  end

  def valid_mime?(value)
    value.is_a?(String) && value.bytesize <= 255 && %r{\A[a-z0-9][a-z0-9.+-]*/[a-z0-9][a-z0-9.+-]*\z}.match?(value)
  end
end
