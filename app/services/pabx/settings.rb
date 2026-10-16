class Pabx::Settings
  PROVIDER = 'pabx_v1'.freeze
  KEYS = %w[enabled provider base_url allow_http_lab expected_tenant test_extension technical_identity timeout_seconds
            sync_enabled interval_seconds window_days overlap_seconds token_path cdr_rows_path cdr_total_path cdr_fields recording_lookup
            cdr_extension_identity cdr_page_parameter cdr_page_size cdr_timezone].freeze
  CDR_FIELDS = %w[unique_id tenant extension caller callee direction status started_at duration_seconds answered_seconds
                  has_recording recording_reference].freeze

  attr_reader :integration

  def initialize(integration)
    @integration = integration
  end

  def data
    integration.pabx_settings
  end

  def enabled?
    data['enabled'] == true
  end

  def sync_enabled?
    enabled? && data['sync_enabled'] == true
  end

  def configured?
    data['base_url'].present? && data['expected_tenant'].present? && integration.pabx_username.present? && integration.pabx_password.present?
  end

  def validate!
    raise Pabx::Error, 'INVALID_SETTINGS' unless data.is_a?(Hash) && (data.keys - KEYS).empty?
    raise Pabx::Error, 'INVALID_PROVIDER' unless data.fetch('provider', PROVIDER) == PROVIDER
    validate_origin! if data['base_url'].present?
    validate_values!
    raise Pabx::Error, 'CONFIGURATION_MISSING' if enabled? && !configured?
  end

  def validate_origin!
    uri = URI(data['base_url'])
    valid = uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && ['', '/'].include?(uri.path)
    secure = uri.scheme == 'https' || (uri.scheme == 'http' && data['allow_http_lab'] == true)
    raise Pabx::Error, 'INVALID_ORIGIN' unless valid && secure
  rescue URI::InvalidURIError, TypeError
    raise Pabx::Error, 'INVALID_ORIGIN'
  end

  def value(key, default)
    data.fetch(key, default)
  end

  def identity(extension)
    raise Pabx::Error, 'INVALID_EXTENSION' unless /\A[0-9]{1,20}\z/.match?(extension.to_s)

    value('technical_identity', 'plain') == 'tenant_prefix' ? "#{data.fetch('expected_tenant')}#{extension}" : extension.to_s
  end

  def public_payload
    { settings: data, username_configured: integration.pabx_username.present?, password_configured: integration.pabx_password.present?,
      configured: configured?, sync: integration.pabx_sync_state, external_homologation: 'pending',
      insecure_http: data['base_url'].to_s.start_with?('http://'), cdr_mapping: 'provisional' }
  end

  def fingerprint
    ordered = data.sort.to_h.transform_values { |value| value.is_a?(Hash) ? value.sort.to_h : value }
    Digest::SHA256.hexdigest([ordered.to_json, integration.pabx_username, integration.pabx_password].to_json)
  end

  private

  def validate_values!
    %w[enabled sync_enabled allow_http_lab].each do |key|
      raise Pabx::Error, 'INVALID_BOOLEAN' if data.key?(key) && ![true, false].include?(data[key])
    end
    { 'timeout_seconds' => 1..30, 'interval_seconds' => 60..86_400, 'window_days' => 1..31, 'overlap_seconds' => 0..600 }.each do |key, range|
      raise Pabx::Error, 'INVALID_LIMIT' if data.key?(key) && !(data[key].is_a?(Integer) && range.cover?(data[key]))
    end
    raise Pabx::Error, 'INVALID_IDENTITY_MODE' unless %w[plain tenant_prefix].include?(value('technical_identity', 'plain'))
    raise Pabx::Error, 'INVALID_IDENTITY_MODE' unless %w[plain tenant_prefix].include?(value('cdr_extension_identity', 'plain'))
    raise Pabx::Error, 'INVALID_PAGINATION' unless [5, 10, 20, 35].include?(value('cdr_page_size', 20))
    parameter = value('cdr_page_parameter', '')
    raise Pabx::Error, 'INVALID_PAGINATION' unless parameter.is_a?(String) && (parameter.empty? || /\Apage\z/.match?(parameter))
    zone = value('cdr_timezone', 'UTC')
    raise Pabx::Error, 'INVALID_TIME_ZONE' unless zone.is_a?(String) && ActiveSupport::TimeZone[zone]
    raise Pabx::Error, 'INVALID_TENANT' if data['expected_tenant'].present? && !/\A[0-9A-Za-z_-]{1,64}\z/.match?(data['expected_tenant'].to_s)
    identity(data['test_extension']) if data['test_extension'].present?
    fields = data.fetch('cdr_fields', {})
    raise Pabx::Error, 'INVALID_MAPPING' unless fields.is_a?(Hash) && (fields.keys - CDR_FIELDS).empty?
    paths = fields.values + %w[token_path cdr_rows_path cdr_total_path].filter_map { |key| data[key] }
    raise Pabx::Error, 'INVALID_MAPPING' unless paths.all? { |path| path.is_a?(String) && /\A[a-zA-Z0-9_]+(?:\.[a-zA-Z0-9_]+)*\z/.match?(path) }
    raise Pabx::Error, 'INVALID_RECORDING_LOOKUP' unless ['', 'uniqueId', 'gravacao', 'link'].include?(value('recording_lookup', ''))
  end
end
