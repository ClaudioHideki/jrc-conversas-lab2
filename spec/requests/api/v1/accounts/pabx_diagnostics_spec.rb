require 'rails_helper'

RSpec.describe 'PABX authorized diagnosis Rails', :pabx, type: :request do
  let(:account) { create(:account) }
  let(:root) { create(:super_admin) }
  let(:path) { "/api/v1/accounts/#{account.id}/telephony_integration/test_connection" }
  let(:settings) { pabx_settings(enabled: false, sync_enabled: false) }
  let(:dashboard_url) { 'https://pbx.example.test/api/v1/admin/dashboard-extension' }
  let(:dashboard) { { accountcode: '8', statusMap: { '81410' => { status: 'FREE' } } } }
  let(:integration) do
    create(:telephony_integration, account: account, history_enabled: false, pabx_settings: settings,
           pabx_username: 'block2b-user-a', pabx_password: 'block2b-secret-a')
  end

  before do
    create(:account_user, account: account, user: root, role: :administrator)
    allow(Resolv).to receive(:getaddresses).with('pbx.example.test').and_return(['93.184.216.34'])
    stub_request(:post, 'https://pbx.example.test/api/v1/auth/login')
      .with(body: { email: 'block2b-user-a', password: 'block2b-secret-a' }.to_json)
      .to_return(body: { token: 'block2b-bearer' }.to_json)
    stub_request(:get, dashboard_url).to_return { { body: dashboard.to_json } }
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/ramais').to_return(body: '[]')
    stub_request(:post, 'https://pbx.example.test/api/v1/admin/ramais/search')
      .with(body: { search: '1410' }.to_json).to_return(body: '[]')
  end

  [{}, { accountcode: nil }, []].each_with_index do |payload, index|
    it "does not report success for an incomplete dashboard #{index + 1}" do
      integration
      stub_request(:get, dashboard_url).to_return(body: payload.to_json)
      post path, headers: root.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('overall' => 'not_verified', 'error' => 'INVALID_RESPONSE')
      expect(a_request(:any, %r{/api/v1/admin/ramais})).not_to have_been_made
      expect(response.body.match?(/block2b-|Bearer/)).to be(false)
    end
  end

  it 'sanitizes invalid JSON without reflecting external content in the diagnosis' do
    integration
    stub_request(:get, dashboard_url).to_return(body: 'block2b-secret-a block2b-bearer')
    post path, headers: root.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('overall' => 'not_verified', 'error' => 'INVALID_RESPONSE')
    expect(response.body.match?(/block2b-|Bearer/)).to be(false)
  end

  it 'does not invent a status or native collaborator when human extension 1410 is absent' do
    integration
    dashboard[:statusMap] = { '89999' => { status: 'BUSY' } }
    stub_request(:post, 'https://pbx.example.test/api/v1/admin/ramais/search').to_return(status: 404)
    expect do
      post path, headers: root.create_new_auth_token
    end.not_to change(SipCredential, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('overall' => 'partial', 'technical_status' => 'unknown',
                                           'collaborators' => [], 'extension_search' => 'NOT_FOUND')
    expect(integration.reload.pabx_settings).to eq(settings)
  end

  it 'does not create a configuration or authenticate when no configuration exists' do
    expect { post path, headers: root.create_new_auth_token }.not_to change(TelephonyIntegration, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('overall' => 'not_verified', 'error' => 'CONFIGURATION_MISSING')
    expect(a_request(:any, %r{https://pbx\.example\.test/})).not_to have_been_made
  end

  it 'rejects a result if credentials changed concurrently and does not overwrite the new configuration' do
    integration
    stub_request(:get, dashboard_url).to_return do
      integration.update!(pabx_password: 'block2b-rotated')
      { body: dashboard.to_json }
    end
    post path, headers: root.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('STALE_CONFIGURATION')
    expect(integration.reload.pabx_password == 'block2b-rotated').to be(true)
    expect(integration.pabx_sync_state).to eq({})
    expect(response.body.match?(/block2b-|Bearer/)).to be(false)
  end

  [nil, {}, [], 'UNRECOGNIZED'].each_with_index do |state, index|
    it "does not invent availability from unsupported extension status #{index + 1}" do
      integration
      create(:sip_credential, account: account, user: root, extension: '1410')
      dashboard[:statusMap]['81410'] = state
      post path, headers: root.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('overall' => 'partial', 'technical_status' => 'unknown')
    end
  end

  it 'checks a disabled configuration explicitly without changing SIP credentials or enabling sync' do
    integration
    credential = create(:sip_credential, account: account, user: root, extension: '1410', username: '81410')
    original = credential.attributes
    fingerprint = Pabx::Settings.new(integration).fingerprint
    post path, headers: root.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('overall' => 'checks_passed', 'external_homologation' => 'pending')
    expect(Pabx::Settings.new(integration.reload).fingerprint).to eq(fingerprint)
    expect(integration.pabx_settings).to eq(settings)
    expect(credential.reload.attributes).to eq(original)
    expect(response.body.match?(/block2b-|Bearer/)).to be(false)
    expect(a_request(:post, 'https://pbx.example.test/api/v1/auth/login')).to have_been_made.once
  end

  [[:get, '/api/v1/admin/ramais', 'null'], [:post, '/api/v1/admin/ramais/search', 'not-json']].each do |method, endpoint, payload|
    it "keeps the diagnosis partial when #{endpoint} returns invalid registry data" do
      integration
      create(:sip_credential, account: account, user: root, extension: '1410')
      stub_request(method, 'https://pbx.example.test' + endpoint).to_return(body: payload)
      post path, headers: root.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('overall' => 'partial', 'extension_registry' => 'partial', 'technical_status' => 'FREE')
      field = method == :get ? 'extensions_list' : 'extension_search'
      expect(response.parsed_body[field]).to eq('INVALID_RESPONSE')
    end
  end
end
