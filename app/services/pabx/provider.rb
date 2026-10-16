class Pabx::Provider
  attr_reader :settings
  EXTENSION_STATUSES = %w[FREE BUSY RINGING UNREGISTERED REGISTERED].freeze

  def initialize(integration)
    @integration = integration
    @settings = Pabx::Settings.new(integration)
    @client = Pabx::Client.new(integration)
  end

  def dashboard
    payload = @client.request(:get, '/api/v1/admin/dashboard-extension')
    accountcode = payload['accountcode'] if payload.is_a?(Hash)
    valid = (accountcode.is_a?(String) || accountcode.is_a?(Integer)) && /\A[0-9A-Za-z_-]{1,64}\z/.match?(accountcode.to_s)
    raise Pabx::Error, 'INVALID_RESPONSE' unless valid

    payload
  end

  def verify_scope!
    result = dashboard
    raise Pabx::Error, 'TENANT_MISMATCH' unless result['accountcode'].to_s == settings.data.fetch('expected_tenant').to_s

    result
  end

  def extensions
    verify_scope!
    @client.request(:get, '/api/v1/admin/ramais')
  end

  def search_extension(extension)
    settings.identity(extension)
    verify_scope!
    @client.request(:post, '/api/v1/admin/ramais/search', { search: extension.to_s })
  end

  def web_extensions
    verify_scope!
    @client.request(:get, '/api/v1/admin/ramais/web')
  end

  def trunks
    verify_scope!
    @client.request(:get, '/api/v1/admin/ramais/my-trunks')
  end

  def extension_status(dashboard, extension)
    raise Pabx::Error, 'TENANT_MISMATCH' unless dashboard.fetch('accountcode').to_s == settings.data.fetch('expected_tenant').to_s

    technical = settings.identity(extension)
    entry = dashboard['statusMap'].is_a?(Hash) ? dashboard['statusMap'][technical] : nil
    state = entry.is_a?(Hash) ? entry['status'] : entry
    status = EXTENSION_STATUSES.include?(state) ? state : 'unknown'
    account = @integration.account
    credentials = account.sip_credentials.includes(:user).where(extension: extension.to_s, user_id: account.users.select(:id))
    collaborators = credentials.map { |credential| { user_id: credential.user_id, name: credential.user.name, enabled: credential.enabled? } }
    { extension: extension.to_s, technical_extension: technical, technical_status: status, collaborators: collaborators }
  end

  def dids
    verify_scope!
    @client.request(:get, '/api/v1/dids')
  end

  def queues
    verify_scope!
    @client.request(:get, '/api/v1/admin/filas')
  end

  def call_history(from:, to:, page:, extension: nil)
    raise Pabx::Error, 'INVALID_PAGINATION' unless page.is_a?(Integer) && page.positive?
    parameter = settings.value('cdr_page_parameter', '')
    raise Pabx::Error, 'CDR_PAGINATION_PENDING' if page > 1 && parameter.blank?
    raise Pabx::Error, 'INVALID_PERIOD' unless from <= to && to - from <= 31.days
    settings.identity(extension) if extension
    verify_scope!
    zone = settings.value('cdr_timezone', 'UTC')
    first = from.in_time_zone(zone)
    last = to.in_time_zone(zone)
    params = { datainicial: first.to_date.iso8601, datafinal: last.to_date.iso8601,
               horainicial: first.strftime('%H:%M'), horafinal: last.strftime('%H:%M'), paginacao: settings.value('cdr_page_size', 20) }
    params[parameter.to_sym] = page if parameter.present?
    params[:ramais] = extension.to_s if extension
    Pabx::Contract.new(settings).page(@client.request(:post, '/api/v1/admin/relatorio-cdr/search', params))
  end

  def recordings_access
    raise Pabx::Error, 'HISTORY_DISABLED' unless settings.enabled?
    verify_scope!
    result = @client.request(:get, '/api/v1/admin/relatorio-cdr/gravacoes-solicitadas')
    valid = result.is_a?(Hash) && result['solicitacoes'].is_a?(Hash) && result['solicitacoes']['data'].is_a?(Array)
    raise Pabx::Error, 'INVALID_RESPONSE' unless valid

    'accessible_not_homologated'
  end

  def recording(record)
    raise Pabx::Error, 'HISTORY_DISABLED' unless settings.enabled?
    unless record.account_id == @integration.account_id && record.provider == Pabx::Settings::PROVIDER
      raise Pabx::Error, 'RECORDING_FORBIDDEN'
    end
    raise Pabx::Error, 'TENANT_MISMATCH' unless record.external_tenant == settings.data.fetch('expected_tenant').to_s
    raise Pabx::Error, 'RECORDING_UNAVAILABLE' unless record.has_recording?
    unless settings.value('recording_lookup', '') == 'link' && Pabx::Contract.recording_link?(record.recording_reference)
      raise Pabx::Error, 'RECORDING_MAPPING_PENDING'
    end
    verify_scope!

    result = @client.request(:post, '/api/v1/admin/relatorio-cdr/download', { link: record.recording_reference }, recording: true)
    supported = %w[audio/wav audio/x-wav audio/mpeg audio/ogg audio/webm audio/mp4 audio/flac application/octet-stream]
    body = result[:body]
    known_audio = (body.start_with?('RIFF') && body.byteslice(8, 4) == 'WAVE') || body.start_with?('ID3', 'OggS', 'fLaC') ||
                  body.start_with?("\x1A\x45\xDF\xA3".b) || (body.byteslice(4, 4) == 'ftyp') ||
                  (body.bytesize >= 2 && body.getbyte(0) == 0xFF && (body.getbyte(1) & 0xE0) == 0xE0)
    raise Pabx::Error, 'INVALID_RECORDING' unless supported.include?(result[:content_type]) && known_audio

    result
  end
end
