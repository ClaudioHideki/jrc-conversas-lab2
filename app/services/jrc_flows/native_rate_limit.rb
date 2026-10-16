require 'openssl'

class JrcFlows::NativeRateLimit
  class Limited < StandardError
    attr_reader :status

    def initialize(status)
      @status = status
      super(status == 429 ? 'FLOW_RATE_LIMITED' : 'FLOW_RATE_LIMIT_UNAVAILABLE')
    end
  end
  SCRIPT = <<~LUA.freeze
    local accepted = 1
    for index, key in ipairs(KEYS) do
      local count = redis.call('INCR', key)
      if count == 1 then redis.call('EXPIRE', key, ARGV[1]) end
      if count > tonumber(ARGV[index + 1]) then accepted = 0 end
    end
    return accepted
  LUA

  def initialize(redis: nil, key: nil)
    @redis = redis || ->(&block) { Redis::Alfred.with(&block) }
    @key = key || Rails.application.key_generator.generate_key('jrc-flow-native-rate-v1', 32)
  end

  def check!(ip:, identity:, audience:)
    raise Limited.new(503) unless %w[callback browser].include?(audience)

    values = ["#{audience}:identity:#{identity}", "#{audience}:ip:#{ip}"]
    keys = values.map { |value| 'jrc-flow-native-rate:' + OpenSSL::HMAC.hexdigest('SHA256', @key, value) }
    accepted = @redis.call { |connection| connection.eval(SCRIPT, keys: keys, argv: [60, 120, 600]) }
    raise Limited.new(429) unless accepted == 1
  rescue Limited
    raise
  rescue StandardError
    raise Limited.new(503)
  end
end
