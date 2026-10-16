require 'net/http'
require 'uri'
require 'json'
require 'timeout'

class JrcFlows::NativeClient
  class Error < StandardError
    attr_reader :status

    def initialize(code, status: 502)
      @status = status
      super(code)
    end
  end
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
  PREFIX = '/v1/flow-delegations'.freeze
  SAFE_CODES = %w[FLOW_ACCESS_DENIED FLOW_CONTEXT_CHANGED FLOW_SESSION_NOT_FOUND FLOW_SESSION_NONCE_REUSED FLOW_ORIGIN_NATIVE_EVIDENCE_REQUIRED
                  FLOW_ORIGIN_CAPABILITY_REQUIRED FLOW_ORIGIN_CAPABILITY_REVOKED FLOW_HOST_AUTHORITY_UNAVAILABLE FLOW_HOST_FENCE_REQUIRED
                  FLOW_REGISTRATION_CHALLENGE_NOT_FOUND FLOW_REGISTRATION_NOT_FOUND FLOW_REGISTRATION_CHALLENGE_CONSUMED
                  FLOW_REGISTRATION_IN_PROGRESS FLOW_REGISTRATION_HOST_UNAVAILABLE FLOW_REGISTRATION_HOST_AUTHORITY_DENIED FLOW_RATE_LIMITED].freeze

  def initialize(origin:, credential:, allowed_origins: nil, transport_factory: nil)
    allowed = allowed_origins || ENV.fetch('JRC_BROKER_ALLOWED_ORIGINS', '').split(',').map(&:strip)
    uri = URI.parse(origin.to_s)
    valid = uri.is_a?(URI::HTTPS) && uri.host && uri.port == 443 && origin == "https://#{uri.host}" && allowed.include?(origin)
    raise Error.new('FLOW_BROKER_ORIGIN_NOT_ALLOWED', status: 422) unless valid
    raise Error.new('FLOW_NATIVE_CREDENTIAL_INVALID', status: 422) unless credential.is_a?(String) && /\A[A-Za-z0-9_-]{43}\z/.match?(credential)

    @origin = origin
    @credential = credential
    @transport_factory = transport_factory || ->(host, port) { Net::HTTP.new(host, port, nil) }
  rescue URI::InvalidURIError
    raise Error.new('FLOW_BROKER_ORIGIN_NOT_ALLOWED', status: 422)
  end

  def inspect
    '#<JrcFlows::NativeClient [FILTERED]>'
  end

  def context(cursor: nil)
    request(:get, '/native-context?limit=25' + (cursor ? "&cursor=#{identifier!(cursor)}" : ''))
  end

  def challenge(id, nonce:)
    request(:get, "/native-registration-challenges/#{identifier!(id)}", nonce: nonce, limit: 65_536)
  end

  def register(challenge_id:, nonce:, callback_credential:)
    request(:post, '/native-registrations', nonce: nonce, limit: 65_536,
                                            body: { challengeId: identifier!(challenge_id), callbackCredential: callback_credential })
  end

  def issue_session(external_actor_id:, nonce:, integration_ids:, scopes:)
    request(:post, '/native-sessions',
            body: { externalActorId: external_actor_id, nonce: identifier!(nonce), integrationIds: integration_ids, scopes: scopes })
  end

  def revoke_session(id, external_actor_id:, nonce:)
    request(:delete, "/native-sessions/#{identifier!(id)}", body: { externalActorId: external_actor_id, nonce: identifier!(nonce) })
  end

  def editor(operation, body: nil, idempotency_key: nil)
    raise Error.new('FLOW_INVALID_REQUEST', status: 400) unless operation.is_a?(JrcFlows::NativeEditorOperation::Operation)

    request(operation.method, operation.path, body: body, limit: operation.response_limit,
                                              request_limit: operation.request_limit, absolute: true, idempotency_key: idempotency_key)
  end

  def claim_installation(id, input)
    request(:post, "/native-installation-grants/#{identifier!(id)}/claim", body: input)
  end

  def renew_installation(id, input)
    request(:post, "/native-installations/#{identifier!(id)}/renew", body: input)
  end

  def revoke_installation(id, input)
    request(:delete, "/native-installations/#{identifier!(id)}", body: input)
  end

  def upload_media(root_id:, channel_id:, io:, byte_size:, mime_type:, kind:, file_name:, idempotency_key:)
    raise Error.new('FLOW_INVALID_REQUEST', status: 400) unless byte_size.is_a?(Integer) && byte_size.positive? && byte_size <= 16 * 1024 * 1024 &&
                                                                mime_type.is_a?(String) &&
                                                                %r{\A[a-z0-9.+-]+/[a-z0-9.+-]+\z}.match?(mime_type) &&
                                                                mime_type.bytesize <= 100 &&
                                                                %w[image audio video document].include?(kind) &&
                                                                file_name.is_a?(String) && /\A[A-Za-z0-9_.!~*'()%-]{1,765}\z/.match?(file_name)

    request(
      :post, "/v1/delegated-flows/#{identifier!(root_id)}/channels/#{identifier!(channel_id)}/media", absolute: true,
      raw_body: io, raw_size: byte_size, request_limit: 16 * 1024 * 1024, idempotency_key: identifier!(idempotency_key),
      media_headers: { 'X-JRC-Media-Mime' => mime_type, 'X-JRC-Media-Kind' => kind, 'X-JRC-Media-Name' => file_name }
    )
  end

  private

  def identifier!(value)
    raise Error.new('FLOW_INVALID_REQUEST', status: 400) unless value.is_a?(String) && UUID.match?(value)

    value
  end

  def request(method, path, nonce: nil, body: nil, limit: 16_384, request_limit: limit, absolute: false, idempotency_key: nil, raw_body: nil,
              raw_size: nil, media_headers: nil)
    raise Error.new('FLOW_INVALID_REQUEST', status: 400) if nonce && !(nonce.is_a?(String) && /\A[A-Za-z0-9_-]{43}\z/.match?(nonce))

    uri = URI.parse(@origin + (absolute ? '' : PREFIX) + path)
    headers = { 'Authorization' => "Bearer #{@credential}", 'Accept' => 'application/json', 'Content-Type' => 'application/json' }
    headers['X-JRC-Flow-Challenge'] = nonce if nonce
    if raw_body
      unless raw_body.respond_to?(:read) && body.nil? && raw_size.is_a?(Integer) && raw_size <= request_limit
        raise Error.new('FLOW_INVALID_REQUEST',
                        status: 400)
      end

      headers.merge!(media_headers)
      headers['Content-Type'] = 'application/octet-stream'
      headers['Content-Length'] = raw_size.to_s
    end
    if idempotency_key
      raise Error.new('FLOW_INVALID_REQUEST', status: 400) unless idempotency_key.is_a?(String) && UUID.match?(idempotency_key)

      headers['Idempotency-Key'] = idempotency_key
    end
    req = Net::HTTP.const_get(method.to_s.capitalize).new(uri.request_uri, headers)
    req.body = JSON.generate(body) unless body.nil?
    req.body_stream = raw_body if raw_body
    raise Error.new('FLOW_REQUEST_TOO_LARGE', status: 413) if req.body && req.body.bytesize > request_limit

    http = @transport_factory.call(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.open_timeout = 3
    http.read_timeout = 3
    http.write_timeout = 3
    http.max_retries = 0
    Timeout.timeout(10) { http.request(req) { |response| return read_response(response, limit) } }
  rescue Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError
    raise Error.new('FLOW_BROKER_UNAVAILABLE', status: 503)
  end

  def read_response(response, limit)
    status = response.code.to_i
    raise Error.new('FLOW_BROKER_REDIRECT_DENIED') if status.between?(300, 399)

    length = response['content-length']
    raise Error.new('FLOW_BROKER_INVALID_RESPONSE') if length && (!/\A[0-9]+\z/.match?(length) || length.to_i > limit)

    bytes = +''
    response.read_body do |chunk|
      bytes << chunk
      raise Error.new('FLOW_BROKER_INVALID_RESPONSE') if bytes.bytesize > limit
    end
    result = JSON.parse(bytes)
    raise Error.new('FLOW_BROKER_INVALID_RESPONSE') unless result.is_a?(Hash)
    return result if [200, 201].include?(status)

    code = SAFE_CODES.include?(result['code']) ? result['code'] : 'FLOW_BROKER_REQUEST_DENIED'
    raise Error.new(code, status: [400, 401, 403, 404, 409, 413, 429, 503].include?(status) ? status : 502)
  rescue JSON::ParserError
    raise Error.new('FLOW_BROKER_INVALID_RESPONSE')
  end
end
