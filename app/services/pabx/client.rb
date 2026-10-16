require 'ssrf_filter'

# SsrfFilter pins a public DNS result, verifies TLS and refuses redirects.
# No response body, URL, credential or provider exception is logged.
class Pabx::Client
  MAX_JSON_BYTES = 2.megabytes
  MAX_RECORDING_BYTES = 20.megabytes

  def initialize(integration)
    @integration = integration
    @settings = Pabx::Settings.new(integration)
    @settings.validate!
    raise Pabx::Error, 'CONFIGURATION_MISSING' unless @settings.configured?
  end

  def inspect
    '#<Pabx::Client [FILTERED]>'
  end

  def request(method, path, payload = nil, recording: false)
    2.times do |attempt|
      response = exchange(method, path, payload, token: token, recording: recording)
      if response[:status] == 401
        Rails.cache.delete(cache_key)
        @token = nil
        next if attempt.zero?
      end
      validate_status!(response[:status])
      return response if recording

      return parse_json(response[:body])
    end
  end

  private

  def token
    @token ||= Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      response = exchange(:post, '/api/v1/auth/login', { email: @integration.pabx_username, password: @integration.pabx_password })
      validate_status!(response[:status])
      result = Pabx::Contract.at(parse_json(response[:body]), @settings.value('token_path', 'token'))
      raise Pabx::Error, 'INVALID_TOKEN_RESPONSE' unless result.is_a?(String) && /\A[!-~]{1,8192}\z/.match?(result)

      ActiveRecord::Encryption.encryptor.encrypt(result)
    end.then { |encrypted| ActiveRecord::Encryption.encryptor.decrypt(encrypted) }
  end

  def cache_key
    "pabx/token/#{@integration.account_id}/#{@integration.id}/#{@settings.fingerprint}"
  end

  def exchange(method, path, payload, token: nil, recording: false)
    url = @settings.data.fetch('base_url').delete_suffix('/') + path
    raise Pabx::Error, 'INVALID_ENDPOINT' unless path.start_with?('/api/v1/') && !path.include?('..')

    headers = { 'Content-Type' => 'application/json', 'Accept' => recording ? 'audio/*,application/octet-stream' : 'application/json' }
    headers['Authorization'] = "Bearer #{token}" if token
    result = nil
    SsrfFilter.public_send(method, url, headers: headers, body: payload&.to_json, max_redirects: 0,
                          http_options: { open_timeout: 3, read_timeout: @settings.value('timeout_seconds', 15),
                                          verify_mode: OpenSSL::SSL::VERIFY_PEER }) do |response|
      result = read_response(response, recording)
    end
    result
  rescue Timeout::Error
    raise Pabx::Error, 'TIMEOUT', cause: nil
  rescue SsrfFilter::Error, Resolv::ResolvError
    raise Pabx::Error, 'UNSAFE_ORIGIN', cause: nil
  rescue SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError
    raise Pabx::Error, 'UNAVAILABLE', cause: nil
  end

  def read_response(response, recording)
    body = +''.b
    response.read_body do |chunk|
      body << chunk
      raise Pabx::Error, 'RESPONSE_TOO_LARGE' if body.bytesize > (recording ? MAX_RECORDING_BYTES : MAX_JSON_BYTES)
    end
    { status: response.code.to_i, body: body, content_type: response['Content-Type'].to_s.split(';').first }
  end

  def validate_status!(status)
    return if (200..299).cover?(status)

    raise Pabx::Error, { 401 => 'INVALID_CREDENTIALS', 403 => 'FORBIDDEN', 404 => 'NOT_FOUND',
                         410 => 'EXPIRED', 422 => 'INVALID_REQUEST', 429 => 'RATE_LIMITED' }.fetch(status, 'PROVIDER_ERROR')
  end

  def parse_json(body)
    value = JSON.parse(body)
    raise Pabx::Error, 'INVALID_RESPONSE' unless value.is_a?(Hash) || value.is_a?(Array)

    value
  rescue JSON::ParserError, TypeError
    raise Pabx::Error, 'INVALID_RESPONSE', cause: nil
  end
end
