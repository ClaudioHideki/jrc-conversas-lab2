# All populated CDR responses in these specs are synthetic/provisional mappings.
module PabxHelpers
  def pabx_settings(overrides = {})
    { 'provider' => 'pabx_v1', 'enabled' => true, 'sync_enabled' => true, 'base_url' => 'https://pbx.example.test',
      'expected_tenant' => '8', 'test_extension' => '1410', 'technical_identity' => 'tenant_prefix',
      'cdr_rows_path' => 'calls', 'cdr_total_path' => 'total', 'cdr_extension_identity' => 'tenant_prefix',
      'cdr_page_parameter' => 'page', 'cdr_timezone' => 'America/Sao_Paulo', 'cdr_fields' => {
        'unique_id' => 'uniqueId', 'tenant' => 'accountcode', 'extension' => 'ramal', 'caller' => 'origem', 'callee' => 'destino',
        'direction' => 'tipo', 'status' => 'status', 'started_at' => 'started_at', 'duration_seconds' => 'duration',
        'answered_seconds' => 'billsec', 'has_recording' => 'gravacao', 'recording_reference' => 'recording_id'
      } }.merge(overrides.stringify_keys)
  end

  def pabx_row(overrides = {})
    { 'uniqueId' => 'synthetic-call-1', 'accountcode' => '8', 'ramal' => '81410', 'origem' => '1410', 'destino' => '+5511999991234',
      'tipo' => 'OUT', 'status' => 'ANSWERED', 'started_at' => Time.current.iso8601, 'duration' => 30, 'billsec' => 20,
      'gravacao' => 'N' }.merge(overrides.stringify_keys)
  end
end

RSpec.configure { |config| config.include PabxHelpers, :pabx }
