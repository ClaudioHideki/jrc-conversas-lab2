require 'faraday'

# No logging, redirects or automatic write retries. An ambiguous write outcome
# must be reconciled by its persisted transaction ID before another send.
class JrcBackoffice::Docusign::Transport
  MAX_BYTES = 20.megabytes

  def initialize
    @http = Faraday.new(request: { timeout: 20, open_timeout: 5 }, ssl: { verify: true })
  end

  def call(method:, url:, headers:, body: nil, format: :json)
    write = method != :get
    response = @http.run_request(method, url, body, headers)
    unless response.success?
      code = response.body.to_s.include?('"consent_required"') ? 'CONSENT_REQUIRED' : 'PROVIDER_REJECTED'
      raise JrcBackoffice::Docusign::Error.new(code: code, http_status: response.status, uncertain: write && response.status >= 500)
    end
    decode(response, format: format, write: write)
  rescue Faraday::Error
    raise JrcBackoffice::Docusign::Error.new(code: 'PROVIDER_UNAVAILABLE', uncertain: write)
  end

  private

  def decode(response, format:, write:)
    bytes = response.body.to_s
    invalid!(write) if bytes.bytesize > MAX_BYTES
    return {} if format == :empty_json && bytes.empty?
    return pdf(bytes, response.headers['content-type']) if format == :pdf

    data = JSON.parse(bytes)
    invalid!(write) unless data.is_a?(Hash)
    data
  rescue JSON::ParserError
    invalid!(write)
  end

  def pdf(bytes, content_type)
    invalid!(false) unless content_type.to_s.split(';').first == 'application/pdf' && bytes.b.start_with?('%PDF-')
    bytes.b
  end

  def invalid!(uncertain)
    raise JrcBackoffice::Docusign::Error.new(code: 'PROVIDER_RESPONSE_INVALID', uncertain: uncertain)
  end
end
