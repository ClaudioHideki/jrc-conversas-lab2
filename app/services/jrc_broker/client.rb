require 'net/http'

class JrcBroker::Client
  class Error < StandardError
    attr_reader :status

    def initialize(code, status: 502)
      @status = status
      super(code)
    end
  end

  PREFIX = '/v1/integrations/chatwoot/control'.freeze
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
  MAX_RESPONSE_BYTES = 2_100_000

  def initialize(origin:, token:, actor_id:)
    @origin = JrcBroker::Configuration.allowed_origin!(origin)
    raise JrcBroker::Configuration::InvalidConfiguration unless token.is_a?(String) && token.bytesize.between?(1, 4096) && /\A[!-~]+\z/.match?(token)

    @token = token
    @actor_id = actor_id.to_s
  end

  def inspect
    '#<JrcBroker::Client [FILTERED]>'
  end

  def context
    request(:get, '/context')
  end

  def resources
    request(:get, '/resources')
  end

  def operations
    request(:get, '/onboarding')
  end

  def start_onboarding(body, key:)
    request(:post, '/onboarding', body: body, key: key)
  end

  def onboarding(id)
    request(:get, "/onboarding/#{identifier!(id)}")
  end

  def recover_onboarding(id, action:, key:)
    request(:post, "/onboarding/#{identifier!(id)}/recover", body: { action: action }, key: key)
  end

  def status(id)
    request(:get, connection_path(id, 'status'))
  end

  def campaign_transport(id)
    request(:get, connection_path(id, 'campaign-transport'))
  end

  def campaign_receipt(id, conversation_id, message_id)
    raise Error.new('JRC_BROKER_INVALID_REQUEST', status: 400) unless message_id.is_a?(Integer) && message_id.positive?

    request(:get, conversation_path(id, conversation_id, "campaign-messages/#{message_id}"))
  end

  def pair(id, key:)
    request(:post, connection_path(id, 'pair'), body: {}, key: key)
  end

  def pair_operation(id, operation_id)
    request(:get, connection_path(id, "pair-operations/#{identifier!(operation_id)}"))
  end

  def disconnect(id, key:)
    request(:post, connection_path(id, 'disconnect'), body: {}, key: key)
  end

  def confirm_identity(id, revision:, key:)
    request(:post, connection_path(id, 'confirm-identity'), body: { observedRevision: revision }, key: key)
  end

  def assign_agents(id, agent_ids:, key:)
    request(:put, connection_path(id, 'agents'), body: { agentIds: agent_ids }, key: key)
  end

  def conversation_attendance(id, conversation_id)
    request(:get, conversation_path(id, conversation_id, 'attendance'))
  end

  def start_conversation_takeover(id, conversation_id, body, key:)
    request(:post, conversation_path(id, conversation_id, 'takeovers'), body: body, key: key)
  end

  def conversation_takeover(id, conversation_id, takeover_id)
    request(:get, conversation_path(id, conversation_id, "takeovers/#{identifier!(takeover_id)}"))
  end

  def complete_conversation_takeover(id, conversation_id, takeover_id, message_id:)
    request(:post, conversation_path(id, conversation_id, "takeovers/#{identifier!(takeover_id)}/complete"), body: { messageId: message_id })
  end

  def cancel_conversation_takeover(id, conversation_id, request_id:, fingerprint:)
    request(:post, conversation_path(id, conversation_id, 'takeovers/cancel'), body: { requestId: request_id, fingerprint: fingerprint })
  end

  private

  def identifier!(id)
    raise Error.new('JRC_BROKER_INVALID_REQUEST', status: 400) unless id.is_a?(String) && UUID.match?(id)

    id
  end

  def connection_path(id, action)
    "/connections/#{identifier!(id)}/#{action}"
  end

  def conversation_path(id, conversation_id, action)
    unless conversation_id.is_a?(Integer) && conversation_id.positive? && conversation_id <= 9_007_199_254_740_991
      raise Error.new('JRC_BROKER_INVALID_REQUEST', status: 400)
    end

    connection_path(id, "conversations/#{conversation_id}/#{action}")
  end

  def request(method, path, body: nil, key: nil)
    uri = URI.parse("#{@origin}#{PREFIX}#{path}")
    req = Net::HTTP.const_get(method.to_s.capitalize).new(uri.request_uri, request_headers(key))
    req.body = JSON.generate(body) unless body.nil?
    http = Net::HTTP.new(uri.host, uri.port, nil)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.open_timeout = 3
    http.read_timeout = 15
    http.write_timeout = 10
    http.max_retries = 0
    http.request(req) { |response| return read_response(response) }
  rescue Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError, JSON::ParserError
    raise Error.new('JRC_BROKER_UNAVAILABLE', status: 503)
  end

  def request_headers(key)
    headers = { 'X-JRC-API-Key' => @token, 'X-JRC-External-Actor' => @actor_id, 'Accept' => 'application/json', 'Content-Type' => 'application/json' }
    headers['Idempotency-Key'] = key if key
    headers
  end

  def read_response(response)
    status = response.code.to_i
    code = { 400 => 'INVALID_REQUEST', 401 => 'FORBIDDEN', 403 => 'FORBIDDEN', 404 => 'NOT_FOUND', 409 => 'CONFLICT' }[status]
    raise Error.new("JRC_BROKER_#{code}", status: status == 401 ? 403 : status) if code
    raise Error, 'JRC_BROKER_UNAVAILABLE' unless [200, 202].include?(status)

    body = +''
    response.read_body do |chunk|
      body << chunk
      raise Error, 'JRC_BROKER_INVALID_RESPONSE' if body.bytesize > MAX_RESPONSE_BYTES
    end
    result = JSON.parse(body)
    raise Error, 'JRC_BROKER_INVALID_RESPONSE' unless result.is_a?(Hash)

    result
  end
end
