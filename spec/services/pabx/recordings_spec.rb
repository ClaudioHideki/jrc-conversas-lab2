require 'rails_helper'

RSpec.describe 'PABX documented recording transport', :pabx do
  let(:integration) do
    create(:telephony_integration, pabx_settings: pabx_settings(recording_lookup: 'link', sync_enabled: false),
           pabx_username: 'synthetic-user', pabx_password: 'synthetic-password')
  end
  let(:record) do
    TelephonyCallRecord.create!(account: integration.account, provider: 'pabx_v1', external_tenant: '8',
                               external_unique_id: 'synthetic-audio', extension: '1410', synced_at: Time.current,
                               has_recording: true, recording_reference: '/var/spool/asterisk/monitor/8/synthetic.wav')
  end
  let(:provider) { Pabx::Provider.new(integration) }
  let(:endpoint) { 'https://pbx.example.test/api/v1/admin/relatorio-cdr/download' }
  let(:audio) { 'RIFF'.b + [36].pack('V') + 'WAVEfmt '.b + [16, 1, 1, 8000, 16000, 2, 16].pack('VvvVVvv') + 'data'.b + [0].pack('V') }
  before do
    allow(Resolv).to receive(:getaddresses).with('pbx.example.test').and_return(['93.184.216.34'])
    stub_request(:post, 'https://pbx.example.test/api/v1/auth/login').to_return(body: { token: 'synthetic-token' }.to_json)
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/dashboard-extension').to_return(body: { accountcode: '8' }.to_json)
    stub_request(:post, endpoint).with(body: { link: '/var/spool/asterisk/monitor/8/synthetic.wav' }.to_json)
      .to_return(body: audio, headers: { 'Content-Type' => 'audio/wav' })
  end

  it 'uses only the documented link body from a persisted CDR without exposing it publicly' do
    result = provider.recording(record)
    expect(result).to include(body: audio, content_type: 'audio/wav')
    expect(record.public_payload(settings: Pabx::Settings.new(integration))[:recording_state]).to eq('requestable')
    expect(record.public_payload.to_json).not_to include('/var/spool', 'synthetic-token', 'recording_reference')
  end

  ['', 'uniqueId', 'gravacao'].each do |lookup|
    it "blocks an unconfirmed recording lookup #{lookup.presence || 'empty'}" do
      integration.update!(pabx_settings: pabx_settings(recording_lookup: lookup))
      expect { provider.recording(record) }.to raise_error(Pabx::Error, 'RECORDING_MAPPING_PENDING')
      expect(a_request(:post, endpoint)).not_to have_been_made
    end
  end

  ['https://internal.example/a', '/etc/passwd', '/var/spool/asterisk/monitor/8/../secret',
   '/var/spool/asterisk/monitor/8/%2e%2e/secret', "/var/spool/asterisk/monitor/8/a\0.wav"].each_with_index do |reference, index|
    it "rejects untrusted stored recording reference #{index + 1}" do
      record.recording_reference = reference
      expect { provider.recording(record) }.to raise_error(Pabx::Error, 'RECORDING_MAPPING_PENDING')
      expect(a_request(:post, endpoint)).not_to have_been_made
    end
  end

  it 'rejects another Account record before authenticating' do
    record.account = create(:account)
    expect { provider.recording(record) }.to raise_error(Pabx::Error, 'RECORDING_FORBIDDEN')
    expect(a_request(:post, 'https://pbx.example.test/api/v1/auth/login')).not_to have_been_made
  end

  it 'rejects another external tenant without modifying the expected scope' do
    record.external_tenant = '12'
    expect { provider.recording(record) }.to raise_error(Pabx::Error, 'TENANT_MISMATCH')
    expect(a_request(:post, endpoint)).not_to have_been_made
  end

  it 'blocks the download when the dashboard returns the mismatched tenant' do
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/dashboard-extension').to_return(body: { accountcode: '12' }.to_json)
    expect { provider.recording(record) }.to raise_error(Pabx::Error, 'TENANT_MISMATCH')
    expect(a_request(:post, endpoint)).not_to have_been_made
  end

  it 'does not presume that a call has a recording' do
    record.has_recording = false
    expect { provider.recording(record) }.to raise_error(Pabx::Error, 'RECORDING_UNAVAILABLE')
  end

  [403, 404, 410].each do |status|
    it "sanitizes unavailable or protected audio HTTP #{status}" do
      stub_request(:post, endpoint).to_return(status: status, body: 'synthetic-token synthetic-password')
      code = { 403 => 'FORBIDDEN', 404 => 'NOT_FOUND', 410 => 'EXPIRED' }.fetch(status)
      expect { provider.recording(record) }.to raise_error(Pabx::Error, code)
    end
  end

  it 'rejects a redirect without forwarding credentials or fetching the target' do
    stub_request(:post, endpoint).to_return(status: 302, headers: { Location: 'http://169.254.169.254/latest' })
    expect { provider.recording(record) }.to raise_error(Pabx::Error, 'UNSAFE_ORIGIN')
    expect(a_request(:any, %r{169\.254\.169\.254})).not_to have_been_made
  end

  it 'rejects HTML and disguised non-audio content' do
    stub_request(:post, endpoint).to_return(body: '<html>not audio</html>', headers: { 'Content-Type' => 'audio/wav' })
    expect { provider.recording(record) }.to raise_error(Pabx::Error, 'INVALID_RECORDING')
  end

  it 'enforces the existing twenty MiB recording response limit' do
    stub_request(:post, endpoint).to_return(body: 'x' * (Pabx::Client::MAX_RECORDING_BYTES + 1), headers: { 'Content-Type' => 'audio/wav' })
    expect { provider.recording(record) }.to raise_error(Pabx::Error, 'RESPONSE_TOO_LARGE')
  end

  it 'reads only documented bulk-request metadata without requesting bulk downloads' do
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/relatorio-cdr/gravacoes-solicitadas')
      .to_return(body: { solicitacoes: { data: [] }, config: nil }.to_json)
    expect(provider.recordings_access).to eq('accessible_not_homologated')
    expect(a_request(:post, %r{/download-massa})).not_to have_been_made
  end

  it 'retains a documented path only when its explicit recording field mapping is configured' do
    path = '/var/spool/asterisk/monitor/8/synthetic.wav'
    contract = Pabx::Contract.new(Pabx::Settings.new(integration))
    expect(contract.normalize(pabx_row(recording_id: path))[:recording_reference]).to eq(path)
    integration.pabx_settings['recording_lookup'] = ''
    expect(contract.normalize(pabx_row(recording_id: path))[:recording_reference]).to be_nil
  end

  [{}, { solicitacoes: [] }].each_with_index do |payload, index|
    it "rejects unrecognized requested-recording metadata #{index + 1}" do
      stub_request(:get, 'https://pbx.example.test/api/v1/admin/relatorio-cdr/gravacoes-solicitadas').to_return(body: payload.to_json)
      expect { provider.recordings_access }.to raise_error(Pabx::Error, 'INVALID_RESPONSE')
    end
  end

  it 'keeps the explicitly mapped recording bound to its imported CDR without downloading during sync' do
    integration.update!(pabx_settings: pabx_settings(recording_lookup: 'link', sync_enabled: true))
    link = '/var/spool/asterisk/monitor/8/synthetic.wav'
    stub_request(:post, 'https://pbx.example.test/api/v1/admin/relatorio-cdr/search')
      .to_return(body: { total: 1, calls: [pabx_row(gravacao: 'S', recording_id: link)] }.to_json)
    expect(Pabx::Sync.new(integration).call).to eq(1)
    imported = TelephonyCallRecord.find_by!(account: integration.account, external_unique_id: 'synthetic-call-1')
    expect(imported).to have_attributes(external_tenant: '8', extension: '1410', recording_reference: link)
    expect(imported.public_payload(settings: Pabx::Settings.new(integration))[:recording_state]).to eq('requestable')
    expect(a_request(:post, endpoint)).not_to have_been_made
    expect(provider.recording(imported)).to include(body: audio, content_type: 'audio/wav')
  end
end
