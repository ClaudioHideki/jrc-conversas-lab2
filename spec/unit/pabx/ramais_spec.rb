require_relative 'unit_helper'

RSpec.describe 'PABX extension diagnostics without database writes' do
  include_context 'PABX configuration unit'
  let(:provider) { Pabx::Provider.new(integration) }
  let(:credentials) { double('account SIP credentials') }
  let(:members) { double('current account user IDs') }
  let(:user) { double('native user', name: 'Synthetic Collaborator') }
  let(:credential) { double('native SIP binding', user_id: 27, user: user, enabled?: true) }
  let(:dashboard) { { 'accountcode' => '8', 'statusMap' => { '81410' => { 'status' => 'FREE' } } } }
  before do
    allow(Resolv).to receive(:getaddresses).with('pbx.example.test').and_return(['93.184.216.34'])
    stub_request(:post, 'https://pbx.example.test/api/v1/auth/login').to_return(body: { token: 'synthetic-token' }.to_json)
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/dashboard-extension').to_return { { body: dashboard.to_json } }
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/ramais').to_return(body: '[]')
    stub_request(:post, 'https://pbx.example.test/api/v1/admin/ramais/search').with(body: { search: '1410' }.to_json).to_return(body: '[]')
    allow(account).to receive(:sip_credentials).and_return(credentials)
    allow(account).to receive(:users).and_return(members)
    allow(members).to receive(:select).with(:id).and_return(members)
    allow(credentials).to receive(:includes).with(:user).and_return(credentials)
    allow(credentials).to receive(:where).with(extension: '1410', user_id: members).and_return([credential])
  end

  %w[FREE BUSY RINGING UNREGISTERED].each do |status|
    it "reads the exact #{status} state for human extension 1410 using technical identity 81410" do
      dashboard['statusMap']['81410']['status'] = status
      result = provider.extension_status(provider.dashboard, '1410')
      expect(result).to include(extension: '1410', technical_extension: '81410', technical_status: status)
    end
  end

  [nil, 'UNKNOWN_FROM_PROVIDER', {}, []].each do |state|
    it "does not invent a status for an unsupported #{state.class}" do
      dashboard['statusMap']['81410'] = state
      expect(provider.extension_status(provider.dashboard, '1410')[:technical_status]).to eq('unknown')
    end
  end

  it 'returns only the native collaborator fields from the current Account and membership scope' do
    expect(provider.extension_status(provider.dashboard, '1410')[:collaborators]).to eq(
      [{ user_id: 27, name: 'Synthetic Collaborator', enabled: true }]
    )
    expect(credentials).to have_received(:where).with(extension: '1410', user_id: members)
  end

  it 'does not create or invent a collaborator when no native binding exists' do
    allow(credentials).to receive(:where).and_return([])
    expect(provider.extension_status(provider.dashboard, '1410')[:collaborators]).to eq([])
  end

  it 'queries list and search with the human extension, never the prefixed identity' do
    provider.extensions
    provider.search_extension('1410')
    expect(a_request(:post, 'https://pbx.example.test/api/v1/admin/ramais/search').with(body: { search: '1410' }.to_json)).to have_been_made.once
    expect(a_request(:post, 'https://pbx.example.test/api/v1/admin/ramais/search').with(body: { search: '81410' }.to_json)).not_to have_been_made
  end

  it 'keeps a compatible diagnosis separate from CDR and recording checks' do
    result = Pabx::Diagnostics.new(integration).call
    expect(result).to include(tenant_compatible: true, overall: 'checks_passed', technical_status: 'FREE',
                              cdr: 'not_checked', recordings: 'not_checked', external_homologation: 'pending')
    expect(a_request(:post, %r{/relatorio-cdr/search})).not_to have_been_made
    expect(a_request(:get, %r{/gravacoes-solicitadas})).not_to have_been_made
  end

  it 'reports a missing extension registry separately without hiding a real technical status' do
    stub_request(:post, 'https://pbx.example.test/api/v1/admin/ramais/search').to_return(status: 404)
    expect(Pabx::Diagnostics.new(integration).call).to include(overall: 'partial', technical_status: 'FREE', extension_search: 'NOT_FOUND')
  end

  it 'blocks dependent queries for expected tenant 8 versus returned accountcode 12 without changing configuration' do
    dashboard['accountcode'] = '12'
    expect(Pabx::Diagnostics.new(integration).call).to include(expected_tenant: '8', returned_accountcode: '12',
      tenant_compatible: false, overall: 'blocked_scope', error: 'TENANT_MISMATCH', cdr: 'blocked_scope', recordings: 'blocked_scope')
    expect(configuration['expected_tenant']).to eq('8')
    expect(a_request(:get, 'https://pbx.example.test/api/v1/admin/ramais')).not_to have_been_made
    expect(a_request(:post, 'https://pbx.example.test/api/v1/admin/ramais/search')).not_to have_been_made
    expect(account).not_to have_received(:sip_credentials)
  end

  %i[extensions web_extensions trunks].each do |operation|
    it "also blocks #{operation} when called directly after a tenant mismatch" do
      dashboard['accountcode'] = '12'
      expect { provider.public_send(operation) }.to raise_error(Pabx::Error, 'TENANT_MISMATCH')
    end
  end

  [nil, {}, [], 'private bearer value', 'x' * 65].each_with_index do |accountcode, index|
    it "does not reflect malformed accountcode case #{index} in a diagnosis" do
      dashboard['accountcode'] = accountcode
      expect(Pabx::Diagnostics.new(integration).call).to include(error: 'INVALID_RESPONSE', overall: 'not_verified')
    end
  end
end
