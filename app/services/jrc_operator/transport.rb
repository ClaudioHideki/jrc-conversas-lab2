require 'net/http'

class JrcOperator::Transport
  REMOTE_ERRORS = {
    429 => ['REMOTE_RATE_LIMITED', 429], 409 => ['REMOTE_CONFLICT', 409], 404 => ['REMOTE_NOT_FOUND', 404],
    401 => ['REMOTE_FORBIDDEN', 403], 403 => ['REMOTE_FORBIDDEN', 403]
  }.freeze

  def initialize(config)
    @config = config
  end

  def inspect
    '#<JrcOperator::Transport [FILTERED]>'
  end

  def request(system, method, path, payload, options = {})
    uri = request_uri(system, method, path, payload)
    req = build_request(system, method, uri, payload, options)
    connection(uri).request(req) { |response| return decode_response(response, pdf: options[:pdf]) }
  rescue KeyError, JSON::ParserError
    raise JrcOperator::Error.new('UNSUPPORTED_RESPONSE_SCHEMA', 502)
  rescue Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError
    raise JrcOperator::Error.new('REMOTE_UNAVAILABLE', 503)
  end

  private

  def request_uri(system, method, path, payload)
    origin = URI(@config.fetch("#{system}_origin"))
    raise JrcOperator::Error, 'INVALID_ORIGIN' unless valid_origin?(origin)

    uri = URI.join(origin.to_s, path)
    uri.query = URI.encode_www_form(payload) if query_request?(system, method)
    uri
  end

  def valid_origin?(origin)
    origin.host.present? && origin.userinfo.nil? && origin.query.nil? && origin.fragment.nil? &&
      ['', '/'].include?(origin.path) && secure_origin?(origin)
  end

  def secure_origin?(origin)
    origin.scheme == 'https' || (Rails.env.test? && origin.scheme == 'http' && origin.host == '127.0.0.1')
  end

  def token_for(system)
    key = @config.fetch("#{system}_token_env")
    raise JrcOperator::Error, 'INVALID_CREDENTIAL_REFERENCE' unless /\AJRC_OPERATOR_[A-Z0-9_]+\z/.match?(key)

    token = ENV.fetch(key)
    raise JrcOperator::Error, 'INVALID_CREDENTIAL' unless token.is_a?(String) && /\A[!-~]{1,256}\z/.match?(token)

    token
  end

  def query_request?(system, method)
    system == :rede && method == :get
  end

  def build_request(system, method, uri, payload, options)
    req = Net::HTTP.const_get(method.to_s.capitalize).new(uri.request_uri)
    req['Accept'] = options[:pdf] ? 'application/pdf' : 'application/json'
    req['Content-Type'] = 'application/json'
    token = token_for(system)
    system == :btv ? req['token'] = token : req['Authorization'] = "Bearer #{token}"
    req['Idempotency-Key'] = options[:key] if options[:key]
    req.body = payload.to_json unless query_request?(system, method)
    req
  end

  def connection(uri)
    http = Net::HTTP.new(uri.host, uri.port, nil)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 3
    http.read_timeout = 15
    http.write_timeout = 5
    http.max_retries = 0
    http
  end

  def decode_response(response, pdf: false)
    validate_status!(response)
    body = bounded_body(response)
    return validated_pdf(response, body) if pdf

    result = JSON.parse(body)
    raise JrcOperator::Error, 'UNSUPPORTED_RESPONSE_SCHEMA' unless result.is_a?(Hash)

    result.fetch('data')
  end

  def validate_status!(response)
    status = response.code.to_i
    error = REMOTE_ERRORS[status]
    raise JrcOperator::Error.new(*error) if error
    raise JrcOperator::Error.new('REMOTE_UNAVAILABLE', 503) unless [200, 201].include?(status)
  end

  def bounded_body(response)
    body = +''.b
    response.read_body do |chunk|
      body << chunk
      raise JrcOperator::Error, 'RESPONSE_TOO_LARGE' if body.bytesize > 4_000_000
    end
    body
  end

  def validated_pdf(response, body)
    valid = response['Content-Type'].to_s.split(';').first == 'application/pdf' && body.start_with?('%PDF-')
    raise JrcOperator::Error, 'INVALID_PDF' unless valid

    body
  end
end
