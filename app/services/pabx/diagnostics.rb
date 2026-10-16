class Pabx::Diagnostics
  def initialize(integration)
    @integration = integration
    @settings = Pabx::Settings.new(integration)
  end

  def call
    provider = Pabx::Provider.new(@integration)
    dashboard = provider.dashboard
    expected = @settings.data.fetch('expected_tenant').to_s
    returned = dashboard.fetch('accountcode').to_s
    extension = @settings.data['test_extension'].to_s
    compatible = expected == returned
    result = { api: 'connected', authentication: 'ok', expected_tenant: expected, returned_accountcode: returned,
               tenant_compatible: compatible, extension: extension,
               external_homologation: 'pending', checked_at: Time.current.iso8601,
               insecure_http: @settings.data['base_url'].to_s.start_with?('http://') }
    unless compatible
      return result.merge(overall: 'blocked_scope', error: 'TENANT_MISMATCH', extension_registry: 'blocked_scope',
                          cdr: 'blocked_scope', recordings: 'blocked_scope')
    end

    result[:extensions_list] = probe { provider.extensions; 'accessible' }
    if extension.present?
      result.merge!(provider.extension_status(dashboard, extension))
      result[:extension_search] = probe { provider.search_extension(extension); 'accessible' }
    end
    verified = result[:extensions_list] == 'accessible' && result[:extension_search] == 'accessible'
    result[:extension_registry] = verified ? 'accessible' : 'partial'
    result[:overall] = verified && result[:technical_status] != 'unknown' && result[:collaborators].present? ? 'checks_passed' : 'partial'
    result[:cdr] = 'not_checked'
    result[:recordings] = 'not_checked'
    result
  rescue Pabx::Error => e
    { error: e.code, overall: 'not_verified', api: 'not_verified', external_homologation: 'pending', checked_at: Time.current.iso8601 }
  end

  private

  def probe
    yield
  rescue Pabx::Error => e
    e.code
  end

end
