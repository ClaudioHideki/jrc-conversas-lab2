require 'jwt'
require 'openssl'
require 'uri'

class JrcBackoffice::Docusign::OauthSession
  ORIGINS = { 'demo' => 'https://account-d.docusign.com', 'production' => 'https://account.docusign.com' }.freeze

  def initialize(integration:, transport:)
    @integration = integration
    @transport = transport
  end

  def inspect
    '#<JrcBackoffice::Docusign::OauthSession [FILTERED]>'
  end

  def headers
    authenticate! unless @expires_at && @expires_at > 60.seconds.from_now
    { 'Authorization' => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
  end

  def base_uri
    headers
    @base_uri
  end

  def authenticate!
    origin = ORIGINS.fetch(@integration.environment)
    assertion = jwt_assertion(origin)
    body = URI.encode_www_form(grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: assertion)
    data = @transport.call(method: :post, url: "#{origin}/oauth/token", body: body,
                           headers: { 'Content-Type' => 'application/x-www-form-urlencoded' })
    token = data['access_token']
    invalid! unless token.is_a?(String) && token.present? && data['expires_in'].to_i > 60
    info = @transport.call(method: :get, url: "#{origin}/oauth/userinfo", headers: { 'Authorization' => "Bearer #{token}" })
    @base_uri = verify_identity!(info)
    @access_token = token
    @expires_at = data['expires_in'].to_i.seconds.from_now
    true
  end

  private

  def jwt_assertion(origin)
    private_key = @integration.credentials['private_key']
    key = OpenSSL::PKey::RSA.new(private_key.to_s)
    raise JrcBackoffice::Docusign::Error.new(code: 'CREDENTIAL_INVALID') unless key.private?

    now = Time.current.to_i
    payload = { iss: @integration.integration_key, sub: @integration.impersonated_user_id, aud: URI(origin).host,
                iat: now, exp: now + 3600, scope: 'signature impersonation' }
    JWT.encode(payload, key, 'RS256')
  rescue OpenSSL::PKey::PKeyError
    raise JrcBackoffice::Docusign::Error.new(code: 'CREDENTIAL_INVALID')
  end

  def verify_identity!(info)
    invalid! unless info['sub'].to_s.casecmp?(@integration.impersonated_user_id)
    account = Array(info['accounts']).find { |row| row['account_id'].to_s.casecmp?(@integration.external_account_id) }
    raise JrcBackoffice::Docusign::Error.new(code: 'ACCOUNT_NOT_AUTHORIZED') unless account

    verify_base_uri!(account['base_uri'])
  end

  def verify_base_uri!(value)
    uri = URI.parse(value.to_s)
    valid_host = uri.host.to_s.match?(/\A[a-z0-9-]+\.docusign\.net\z/i)
    demo_host = (@integration.environment == 'demo') == (uri.host == 'demo.docusign.net')
    invalid! unless valid_host && demo_host && secure_origin?(uri)
    invalid! unless ['', '/'].include?(uri.path)
    "https://#{uri.host}"
  rescue URI::InvalidURIError
    invalid!
  end

  def secure_origin?(uri)
    uri.scheme == 'https' && uri.port == 443 && [uri.userinfo, uri.query, uri.fragment].all?(&:nil?)
  end

  def invalid!
    raise JrcBackoffice::Docusign::Error.new(code: 'AUTHORIZATION_INVALID')
  end
end
