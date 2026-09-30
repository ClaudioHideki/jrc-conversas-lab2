require 'net/http'

class JrcNico::RuntimeClient
  class Error < StandardError
    CODES = %w[provider_outer_json_invalid tool_arguments_invalid provider_schema_invalid provider_timeout provider_unauthorized
               provider_forbidden provider_rate_limited provider_unavailable provider_transport_error provider_usage_invalid
               runtime_busy request_cancelled runtime_internal_error unauthorized account_not_configured runtime_transport_error
               runtime_timeout invalid_response invalid_scope invalid_configuration context_too_large invalid_transcription].freeze
    attr_reader :code

    def initialize(code = 'invalid_response')
      @code = CODES.include?(code) ? code : 'invalid_response'
      super(@code)
    end

    def user_message(previous_changes: false)
      case code
      when 'provider_outer_json_invalid', 'tool_arguments_invalid', 'provider_schema_invalid', 'invalid_response'
        unchanged = previous_changes ? 'As etapas já concluídas foram preservadas; esta etapa não realizou alterações.' : 'Nenhuma alteração foi realizada.'
        "O NICO não conseguiu interpretar os dados necessários para executar esta ação. #{unchanged} Tente novamente ou revise os dados informados."
      when 'provider_rate_limited' then 'O provedor de IA atingiu o limite de solicitações ou de uso. Aguarde e verifique a cota do provedor.'
      when 'provider_timeout' then 'O provedor de IA demorou além do limite. A etapa não foi executada. Tente novamente.'
      when 'provider_unauthorized', 'provider_forbidden' then 'O provedor de IA recusou o acesso. Solicite a revisão da configuração ao administrador.'
      when 'runtime_busy' then 'O NICO está ocupado com outras solicitações. Aguarde e tente novamente.'
      when 'account_not_configured' then 'Esta conta não está autorizada no runtime do NICO. Solicite a revisão ao administrador.'
      when 'unauthorized' then 'A autenticação entre o JRC e o runtime do NICO foi recusada. Solicite a revisão ao administrador.'
      when 'runtime_transport_error', 'runtime_timeout' then 'O JRC não conseguiu se comunicar com o runtime do NICO. Tente novamente quando o serviço estiver disponível.'
      when 'request_cancelled' then 'A solicitação do NICO foi cancelada antes da execução desta etapa.'
      else 'O serviço de IA está indisponível. Esta etapa não foi executada. Aguarde e tente novamente.'
      end
    end
  end

  KEYS = %w[request_id account_id summary suggested_reply evidence warnings usage model mode].freeze

  def transcribe(payload)
    body = transport('/v1/transcribe', payload.to_json, account_id: payload.fetch(:account_id), max_bytes: 5_600_000)
    valid = body.is_a?(Hash) && body.keys.sort == %w[account_id mode model request_id text usage]
    valid &&= body['account_id'] == payload[:account_id] && body['request_id'] == payload[:request_id]
    valid &&= body['mode'] == 'provider' && text?(body['text'], 4000) && text?(body['model'], 150, required: true) && valid_usage?(body)
    raise Error, 'invalid_transcription' unless valid

    body
  end

  def operate(payload)
    body = transport('/v1/operate', payload.to_json, account_id: payload.fetch(:account_id))
    estimated = body.is_a?(Hash) && body.delete('usage_estimated')
    raise Error, 'invalid_response' unless estimated.nil? || estimated == true

    fields = payload[:kind] == 'customer' ? %w[reply summary handoff create_lead operator_request] : %w[reply tool arguments]
    raise Error, 'invalid_response' unless body.is_a?(Hash) && body.keys.sort == (fields + %w[request_id account_id usage model mode]).sort
    raise Error, 'invalid_scope' unless body['account_id'] == payload[:account_id] && body['request_id'] == payload[:request_id]
    raise Error, 'invalid_response' unless text?(body['reply'], 4000) && valid_usage?(body) && %w[fixture provider].include?(body['mode'])

    if payload[:kind] == 'customer'
      raise Error, 'invalid_response' unless text?(body['summary'], 8000) && text?(body['operator_request'], 2000) && [true, false].include?(body['handoff']) &&
                                              [true, false].include?(body['create_lead'])
    else
      raise Error, 'invalid_response' unless text?(body['tool'], 80) && text?(body['arguments'], 12_000) && body['arguments'].bytesize <= 12_000

      begin
        body['arguments'] = JSON.parse(body['arguments'], max_nesting: 8)
      rescue JSON::ParserError
        raise Error, 'tool_arguments_invalid'
      end
      raise Error, 'tool_arguments_invalid' unless body['arguments'].is_a?(Hash) && bounded_arguments?(body['arguments'])
    end
    body['usage_estimated'] = true if estimated
    body
  rescue Error => e
    Rails.logger.warn("NICO operation failed request_id=#{payload[:request_id]} code=#{e.code}")
    raise
  end

  def analyze(run, context)
    payload = { request_id: run.request_id, account_id: run.account_id, agent_key: run.agent_key, message: run.message, context: context, history: [] }.to_json
    validate!(transport('/v1/analyze', payload, account_id: run.account_id), run, context)
  end

  private

  def runtime_credentials(account_id)
    raise Error, 'invalid_scope' unless account_id.is_a?(Integer) && account_id.positive?

    routes_json = ENV['NICO_RUNTIME_ROUTES']
    return [ENV.fetch('NICO_RUNTIME_URL'), ENV.fetch('NICO_SERVICE_TOKEN')] if routes_json.blank?

    # Only installation configuration can select an endpoint or a credential.
    # An unmapped Account must never fall back to another tenant's runtime.
    routes = JSON.parse(routes_json)
    raise Error, 'invalid_configuration' unless routes.is_a?(Hash)

    route = routes[account_id.to_s]
    raise Error, 'account_not_configured' unless route
    raise Error, 'invalid_configuration' unless route.is_a?(Hash) && route.keys.sort == %w[token_env url]
    raise Error, 'invalid_configuration' unless route['url'].is_a?(String) && route['token_env'].is_a?(String) &&
                                              route['token_env'].match?(/\ANICO_RUNTIME_TOKEN_[A-Z0-9_]+\z/)

    [route['url'], ENV.fetch(route['token_env'])]
  rescue JSON::ParserError, KeyError
    raise Error, 'invalid_configuration'
  end

  def transport(path, payload, account_id:, max_bytes: 262_144)
    endpoint, token = runtime_credentials(account_id)
    uri = URI(endpoint)
    raise Error, 'invalid_configuration' unless %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil? &&
                                              uri.query.nil? && uri.fragment.nil? && ['', '/'].include?(uri.path) && token.length >= 32

    raise Error, 'context_too_large' if payload.bytesize > max_bytes

    request = Net::HTTP::Post.new(path, { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' })
    request.body = payload
    body = +''
    status = nil
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 3, read_timeout: 55, write_timeout: 10) do |http|
      http.request(request) do |response|
        status = response.code

        response.read_body do |chunk|
          body << chunk
          raise Error, 'invalid_response' if body.bytesize > 131_072
        end
      end
    end
    parsed = JSON.parse(body)
    unless status == '200'
      code = parsed.is_a?(Hash) && parsed['error']
      raise Error, code.is_a?(String) && Error::CODES.include?(code) ? code : 'runtime_transport_error'
    end
    parsed
  rescue KeyError, URI::InvalidURIError
    raise Error, 'invalid_configuration'
  rescue JSON::ParserError
    raise Error, 'invalid_response'
  rescue Timeout::Error
    raise Error, 'runtime_timeout'
  rescue IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
    raise Error, 'runtime_transport_error'
  end

  private

  def validate!(body, run, context)
    valid = body.is_a?(Hash) && body.keys.sort == KEYS.sort
    valid &&= body['account_id'] == run.account_id && body['request_id'] == run.request_id
    valid &&= text?(body['summary'], 8000, required: true) && text?(body['suggested_reply'], 4000) && text?(body['model'], 150, required: true)
    valid &&= %w[fixture provider].include?(body['mode'])
    valid &&= body['warnings'].is_a?(Array) && body['warnings'].length <= 10 && body['warnings'].all? { |warning| text?(warning, 1000) }
    valid &&= body['evidence'].is_a?(Array) && body['evidence'].length <= 30
    allowed = context.values.flatten.map { |item| item.stringify_keys.slice('source', 'reference') }
    valid &&= body['evidence'].all? { |item| item.is_a?(Hash) && item.keys.sort == %w[reference source] && allowed.include?(item) }
    valid &&= valid_usage?(body)
    raise Error, 'invalid_response' unless valid

    body
  end

  def bounded_arguments?(value, depth = 1)
    return false if depth > 8
    return value.values.all? { |child| bounded_arguments?(child, depth + 1) } if value.is_a?(Hash)
    return value.all? { |child| bounded_arguments?(child, depth + 1) } if value.is_a?(Array)
    return value.abs <= 9_007_199_254_740_991 if value.is_a?(Integer)
    return value.finite? if value.is_a?(Float)

    true
  end

  def text?(value, max, required: false)
    value.is_a?(String) && value.length <= max && (!required || value.present?)
  end

  def valid_usage?(body)
    usage = body['usage']
    return usage.nil? if body['mode'] == 'fixture'
    return false unless usage.is_a?(Hash) && usage.keys.sort == %w[input_tokens output_tokens total_tokens]
    return false unless usage.values.all? { |value| value.is_a?(Integer) && value.between?(0, 270_000) }

    usage['input_tokens'] + usage['output_tokens'] == usage['total_tokens']
  end
end
