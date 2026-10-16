require 'rails_helper'

RSpec.describe Pabx::Provider, :pabx do
  let(:integration) { create(:telephony_integration, pabx_settings: pabx_settings, pabx_username: 'synthetic-user', pabx_password: 'synthetic-password') }
  let(:client) { instance_double(Pabx::Client) }
  let(:provider) { described_class.new(integration) }
  before { allow(Pabx::Client).to receive(:new).with(integration).and_return(client) }

  it 'keeps the configured expected tenant when the returned accountcode differs' do
    allow(Pabx::Client).to receive(:new).and_call_original
    allow(Resolv).to receive(:getaddresses).with('pbx.example.test').and_return(['93.184.216.34'])
    stub_request(:post, 'https://pbx.example.test/api/v1/auth/login').to_return(body: { token: 'synthetic-token' }.to_json)
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/dashboard-extension').to_return(body: { accountcode: '12' }.to_json)
    result = Pabx::Diagnostics.new(integration).call
    expect(result).to include(expected_tenant: '8', returned_accountcode: '12', tenant_compatible: false,
                              error: 'TENANT_MISMATCH', overall: 'blocked_scope', cdr: 'blocked_scope', recordings: 'blocked_scope')
    expect(integration.reload.pabx_settings['expected_tenant']).to eq('8')
    expect(a_request(:get, 'https://pbx.example.test/api/v1/admin/ramais')).not_to have_been_made
  end

  it 'reports technical state and a missing registry without querying CDR or recordings' do
    allow(Pabx::Client).to receive(:new).and_call_original
    allow(Resolv).to receive(:getaddresses).with('pbx.example.test').and_return(['93.184.216.34'])
    stub_request(:post, 'https://pbx.example.test/api/v1/auth/login').to_return(body: { token: 'synthetic-token' }.to_json)
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/dashboard-extension')
      .to_return(body: { accountcode: '8', statusMap: { '81410' => { status: 'FREE' } } }.to_json)
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/ramais').to_return(body: '[]')
    stub_request(:post, 'https://pbx.example.test/api/v1/admin/ramais/search').to_return(status: 404)
    expect(Pabx::Diagnostics.new(integration).call).to include(
      tenant_compatible: true, extension: '1410', technical_extension: '81410', technical_status: 'FREE',
      extension_registry: 'partial', extension_search: 'NOT_FOUND', cdr: 'not_checked', recordings: 'not_checked', external_homologation: 'pending'
    )
    expect(a_request(:post, %r{/relatorio-cdr/search})).not_to have_been_made
    expect(a_request(:get, %r{/gravacoes-solicitadas})).not_to have_been_made
  end

  it 'passes documented CDR filters with bounded page numbers and human extension' do
    allow(Pabx::Client).to receive(:new).and_call_original
    allow(Resolv).to receive(:getaddresses).with('pbx.example.test').and_return(['93.184.216.34'])
    stub_request(:post, 'https://pbx.example.test/api/v1/auth/login').to_return(body: { token: 'synthetic-token' }.to_json)
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/dashboard-extension').to_return(body: { accountcode: '8' }.to_json)
    request = stub_request(:post, 'https://pbx.example.test/api/v1/admin/relatorio-cdr/search')
              .with(body: hash_including('ramais' => '1410', 'paginacao' => 20, 'page' => 2,
                                        'datainicial' => '2026-10-15', 'datafinal' => '2026-10-15'))
              .to_return(body: { total: 0 }.to_json)
    provider.call_history(from: Time.zone.parse('2026-10-15T08:00:00-03:00'), to: Time.zone.parse('2026-10-15T18:00:00-03:00'), page: 2, extension: '1410')
    expect(request).to have_been_requested.once
  end

  ['/api/v1/dids', '/api/v1/admin/filas'].each do |path|
    it "treats an empty #{path} list as valid after verifying scope" do
      allow(client).to receive(:request).with(:get, '/api/v1/admin/dashboard-extension').and_return('accountcode' => '8')
      allow(client).to receive(:request).with(:get, path).and_return([])
      expect(path.end_with?('dids') ? provider.dids : provider.queues).to eq([])
    end
  end

  it 'blocks a recording without an explicitly configured provisional lookup' do
    allow(client).to receive(:request).with(:get, '/api/v1/admin/dashboard-extension').and_return('accountcode' => '8')
    record = TelephonyCallRecord.new(account: integration.account, provider: 'pabx_v1', has_recording: true,
                                    external_tenant: '8', external_unique_id: 'synthetic-call-1')
    expect { provider.recording(record) }.to raise_error(Pabx::Error, 'RECORDING_MAPPING_PENDING')
  end
end
