require 'rails_helper'

RSpec.describe 'PABX Provider native Rails scope', :pabx do
  let(:integration) do
    create(:telephony_integration, history_enabled: false,
           pabx_settings: pabx_settings(enabled: false, sync_enabled: false),
           pabx_username: 'synthetic-user', pabx_password: 'synthetic-password')
  end
  let(:provider) { Pabx::Provider.new(integration) }
  let(:dashboard) { { accountcode: '8', statusMap: { '81410' => { status: 'FREE' } } } }

  before do
    allow(Resolv).to receive(:getaddresses).with('pbx.example.test').and_return(['93.184.216.34'])
    stub_request(:post, 'https://pbx.example.test/api/v1/auth/login')
      .with(body: { email: 'synthetic-user', password: 'synthetic-password' }.to_json)
      .to_return(body: { token: 'synthetic-token' }.to_json)
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/dashboard-extension').to_return { { body: dashboard.to_json } }
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/ramais').to_return(body: '[]')
    stub_request(:post, 'https://pbx.example.test/api/v1/admin/ramais/search')
      .with(body: { search: '1410' }.to_json).to_return(body: '[]')
  end

  %i[extensions search_extension web_extensions trunks].each do |operation|
    it "blocks #{operation} on tenant mismatch before any dependent request" do
      dashboard[:accountcode] = '12'
      args = operation == :search_extension ? ['1410'] : []
      original = integration.reload.attributes
      expect { provider.public_send(operation, *args) }.to raise_error(Pabx::Error, 'TENANT_MISMATCH')
      expect(a_request(:any, %r{/api/v1/admin/ramais})).not_to have_been_made
      expect(integration.reload.attributes).to eq(original)
    end
  end

  [[], {}, { accountcode: nil }, { accountcode: [] }, { accountcode: {} }, { accountcode: '' }, { accountcode: 'x' * 65 }].each_with_index do |payload, index|
    it "rejects malformed dashboard case #{index + 1}" do
      stub_request(:get, 'https://pbx.example.test/api/v1/admin/dashboard-extension').to_return(body: payload.to_json)
      expect { provider.dashboard }.to raise_error(Pabx::Error, 'INVALID_RESPONSE')
      expect(a_request(:any, %r{/api/v1/admin/ramais})).not_to have_been_made
    end
  end

  it 'uses the existing Client with the current Account credentials and sends the human search extension' do
    expect(Pabx::Client).to receive(:new).with(integration).and_call_original
    original = integration.reload.attributes
    provider.extensions
    provider.search_extension('1410')
    expect(a_request(:post, 'https://pbx.example.test/api/v1/auth/login')).to have_been_made.once
    expect(a_request(:post, 'https://pbx.example.test/api/v1/admin/ramais/search')
      .with(body: { search: '1410' }.to_json)).to have_been_made.once
    expect(integration.reload.attributes).to eq(original)
  end

  it 'does not associate a SIP technical username or technical extension with human extension 1410' do
    account = integration.account
    user = create(:user, account: account)
    credential = create(:sip_credential, account: account, user: user, extension: '81410', username: '81410')
    original = credential.attributes
    expect { provider.extension_status(provider.dashboard, '1410') }.not_to change(SipCredential, :count)
    expect(provider.extension_status(provider.dashboard, '1410')).to include(
      extension: '1410', technical_extension: '81410', technical_status: 'FREE', collaborators: []
    )
    expect(credential.reload.attributes).to eq(original)
  end

  it 'excludes a native SIP binding after the user loses Account membership' do
    account = integration.account
    user = create(:user, account: account)
    credential = create(:sip_credential, account: account, user: user, extension: '1410')
    account.account_users.find_by!(user_id: user.id).destroy!
    expect(credential.reload).to be_persisted
    expect(provider.extension_status(provider.dashboard, '1410')[:collaborators]).to eq([])
  end

  it 'returns unknown and an empty native binding list for a missing human extension' do
    dashboard[:statusMap] = { '89999' => { status: 'BUSY' } }
    expect(provider.extension_status(provider.dashboard, '1410')).to include(
      extension: '1410', technical_extension: '81410', technical_status: 'unknown', collaborators: []
    )
    expect(integration.account.sip_credentials).to be_empty
  end

  it 'rejects incomplete configuration without authenticating or creating an integration' do
    missing = TelephonyIntegration.new(account: integration.account, history_enabled: false)
    expect { Pabx::Provider.new(missing) }.to raise_error(Pabx::Error, 'CONFIGURATION_MISSING')
    expect(a_request(:post, 'https://pbx.example.test/api/v1/auth/login')).not_to have_been_made
  end

  it 'rejects an invalid origin before authenticating' do
    integration.pabx_settings = integration.pabx_settings.merge('base_url' => 'http://pbx.example.test')
    expect { Pabx::Provider.new(integration) }.to raise_error(Pabx::Error, 'INVALID_ORIGIN')
    expect(a_request(:post, 'https://pbx.example.test/api/v1/auth/login')).not_to have_been_made
  end

  it 'uses only the configuration and native collaborators of each Account' do
    other = create(:telephony_integration, history_enabled: false,
                   pabx_settings: pabx_settings(expected_tenant: '99', enabled: false, sync_enabled: false),
                   pabx_username: 'block2b-user-b', pabx_password: 'block2b-secret-b')
    own_user = create(:user, account: integration.account)
    other_user = create(:user, account: other.account)
    create(:sip_credential, account: integration.account, user: own_user, extension: '1410')
    create(:sip_credential, account: other.account, user: other_user, extension: '1410')
    stub_request(:post, 'https://pbx.example.test/api/v1/auth/login')
      .with(body: { email: 'block2b-user-b', password: 'block2b-secret-b' }.to_json)
      .to_return(body: { token: 'block2b-bearer' }.to_json)
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/dashboard-extension')
      .with(headers: { Authorization: 'Bearer block2b-bearer' })
      .to_return(body: { accountcode: '99', statusMap: { '991410' => { status: 'BUSY' } } }.to_json)
    second = Pabx::Provider.new(other)
    expect(provider.extension_status(provider.dashboard, '1410')[:collaborators].pluck(:user_id)).to eq([own_user.id])
    result = second.extension_status(second.dashboard, '1410')
    expect(result[:collaborators].pluck(:user_id)).to eq([other_user.id])
    expect(result).to include(technical_extension: '991410', technical_status: 'BUSY')
  end
end
