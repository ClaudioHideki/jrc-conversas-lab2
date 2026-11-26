# frozen_string_literal: true

require 'net/http'

# Reads the provider's real catalogue; no inference, credits or estimated models.
class JrcAi::ModelCatalogue
  class Error < StandardError; end

  BASES = { 'openai' => 'https://api.openai.com/v1', 'anthropic' => 'https://api.anthropic.com/v1',
            'google_gemini' => 'https://generativelanguage.googleapis.com/v1beta' }.freeze

  def self.fetch(provider)
    raise Error, 'Informe a chave da API.' unless provider.api_key_configured?
    raise Error, 'Este provedor precisa de uma URL compatível com OpenAI.' if provider.provider_type == 'azure_openai'

    base = provider.request_base_url
    canonical = BASES[provider.provider_type]
    raise Error, 'A URL não corresponde ao provedor selecionado.' if canonical && base != canonical

    uri = URI.parse("#{base}/models")
    hosts = ENV.fetch('NICO_PROVIDER_ALLOWED_HOSTS', 'api.openai.com').split(',').map(&:strip)
    allowed = canonical || hosts.include?(uri.host)
    raise Error, 'URL de provedor não autorizada.' unless allowed && uri.is_a?(URI::HTTPS) && uri.port == 443 &&
                                                            [uri.userinfo, uri.query, uri.fragment].all?(&:nil?)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 20
    rows = []
    # Provider cursors only; never follow redirects or response URLs with credentials.
    10.times do
      request = Net::HTTP::Get.new(uri)
      case provider.provider_type
      when 'anthropic'
        request['Authorization'] = "Bearer #{provider.api_key}"
        request['anthropic-version'] = '2026-10-21'
        workspace = provider.settings['workspace_id']
        if workspace.present?
          raise Error, 'Workspace Anthropic inválido.' unless workspace.match?(/\Awrkspc_[a-zA-Z0-9]{10,100}\z/)

          request['anthropic-workspace-id'] = workspace
        end
      when 'google_gemini' then request['x-goog-api-key'] = provider.api_key
      else request['Authorization'] = "Bearer #{provider.api_key}"
      end
      text = +''
      http.request(request) do |response|
        unless response.code == '200'
          message = provider.provider_type == 'anthropic' && response.code == '400' && provider.settings['workspace_id'].blank? ?
            'Esta chave Anthropic pode exigir o ID do workspace. Informe-o e consulte novamente.' : "O provedor recusou a consulta (HTTP #{response.code})."
          raise Error, message
        end

        response.read_body do |part|
          text << part
          raise Error, 'Catálogo maior que o limite permitido.' if text.bytesize > 1_048_576
        end
      end
      body = JSON.parse(text)
      data = provider.provider_type == 'google_gemini' ? body.fetch('models') : body.fetch('data')
      data.each do |model|
        id = (model['id'] || model['name']).to_s.delete_prefix('models/')
        next unless id.match?(/\A[a-zA-Z0-9._:\/-]{1,150}\z/)
        next if provider.provider_type == 'google_gemini' && !Array(model['supportedGenerationMethods']).include?('generateContent')
        next if provider.provider_type == 'openai' && !id.match?(/\A(gpt-|o[134])/)
        next if provider.provider_type == 'anthropic' && (!id.start_with?('claude-') || model.dig('capabilities', 'structured_outputs', 'supported') == false || model['lifecycle'] == 'retired')
        next if id.match?(/embedding|tts|transcrib|audio|realtime|moderation|image|vision-preview|instruct|search|codex/i)

        rows << { id: id, name: model['display_name'] || model['displayName'] || id, family: model['line'] }
      end
      cursor = if provider.provider_type == 'anthropic' && body['has_more']
                 { after_id: body.fetch('last_id'), limit: 100 }
               elsif provider.provider_type == 'google_gemini' && body['nextPageToken'].present?
                 { pageToken: body['nextPageToken'], pageSize: 100 }
               end
      return { models: rows.uniq { |row| row[:id] }, base_url: base, observed_at: Time.current.iso8601 } unless cursor

      uri.query = URI.encode_www_form(cursor)
    end
    raise Error, 'O catálogo excedeu o limite de páginas.'
  rescue URI::InvalidURIError, JSON::ParserError, KeyError, TypeError, IOError, SystemCallError, Timeout::Error, SocketError, OpenSSL::SSL::SSLError
    raise Error, 'Não foi possível consultar o catálogo do provedor.'
  end
end
