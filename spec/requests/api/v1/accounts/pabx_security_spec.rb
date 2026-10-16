require 'rails_helper'

RSpec.describe 'PABX persistence and HTTP isolation', :pabx, type: :request do
  let(:account) { create(:account) }
  let(:root) { create(:super_admin) }
  let(:path) { "/api/v1/accounts/#{account.id}/telephony_integration" }
  let(:settings) { pabx_settings(enabled: false, sync_enabled: false) }
  let(:integration) do
    create(:telephony_integration, account: account, history_enabled: false, pabx_settings: settings,
           pabx_username: 'block2b-user-a', pabx_password: 'block2b-secret-a')
  end

  before { create(:account_user, account: account, user: root, role: :administrator) }

  it 'persistence encrypts both credential columns in PostgreSQL and decrypts through the backend' do
    integration
    raw = ActiveRecord::Base.connection.select_one(
      "SELECT pabx_username, pabx_password FROM telephony_integrations WHERE id = #{integration.id}"
    )
    expect(raw.values.any? { |value| value.include?('block2b-user-a') || value.include?('block2b-secret-a') }).to be(false)
    expect(raw.values.all? { |value| JSON.parse(value).keys.include?('p') }).to be(true)
    reread = TelephonyIntegration.find(integration.id)
    expect(reread.pabx_username == 'block2b-user-a' && reread.pabx_password == 'block2b-secret-a').to be(true)
    expect(Pabx::Settings.new(reread).enabled?).to be(false)
    expect(Pabx::Settings.new(reread).sync_enabled?).to be(false)
  end

  it 'persistence rotates credentials through HTTP without exposing or activating them' do
    old_ciphertext = integration.pabx_password_before_type_cast
    patch path, params: { settings: settings, api_password: 'block2b-rotated' }, headers: root.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(integration.reload.pabx_password == 'block2b-rotated').to be(true)
    expect(integration.pabx_password_before_type_cast == old_ciphertext).to be(false)
    expect(integration.pabx_username == 'block2b-user-a').to be(true)
    expect(response.body.match?(/block2b-|Bearer/)).to be(false)
    expect(response.parsed_body['settings']).to include('enabled' => false, 'sync_enabled' => false)
    expect(enqueued_jobs.none? { |job| job[:job] == Pabx::SyncJob }).to be(true)
  end

  it 'persistence separates credentials and configurations between two Accounts' do
    other = create(:telephony_integration, history_enabled: false, pabx_settings: settings.merge('expected_tenant' => '99'),
                   pabx_username: 'block2b-user-b', pabx_password: 'block2b-secret-b')
    integration.update!(pabx_password: 'block2b-rotated')
    expect(other.reload.pabx_password == 'block2b-secret-b').to be(true)
    expect(other.pabx_settings['expected_tenant']).to eq('99')
    expect(integration.reload.pabx_settings['expected_tenant']).to eq('8')
    get path, headers: root.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['settings']['expected_tenant']).to eq('8')
    expect(response.body.match?(/block2b-|Bearer/)).to be(false)
  end

  it 'HTTP rejects anonymous reads writes and diagnostics without altering persisted settings' do
    original = integration.reload.attributes
    get path
    expect(response).to have_http_status(:unauthorized)
    patch path, params: { settings: settings }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "#{path}/test_connection"
    expect(response).to have_http_status(:unauthorized)
    expect(integration.reload.attributes).to eq(original)
  end

  it 'HTTP rejects a SuperAdmin lacking membership in the target Account' do
    foreign = create(:telephony_integration, history_enabled: false, pabx_settings: settings,
                     pabx_username: 'block2b-user-b', pabx_password: 'block2b-secret-b')
    original = foreign.reload.attributes
    foreign_path = "/api/v1/accounts/#{foreign.account_id}/telephony_integration"
    headers = root.create_new_auth_token
    get foreign_path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    patch foreign_path, params: { settings: settings, api_password: 'block2b-rotated' }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "#{foreign_path}/test_connection", headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(foreign.reload.attributes).to eq(original)
    expect(response.body.match?(/block2b-|Bearer/)).to be(false)
  end

  it 'HTTP blocks ordinary members from reading or modifying an existing configuration' do
    original = integration.reload.attributes
    [:agent, :administrator].each do |role|
      user = create(:user, account: account, role: role)
      headers = user.create_new_auth_token
      get path, headers: headers
      expect(response).to have_http_status(:forbidden)
      patch path, params: { settings: settings, api_password: 'block2b-rotated' }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{path}/test_connection", headers: headers
      expect(response).to have_http_status(:forbidden)
    end
    expect(integration.reload.attributes).to eq(original)
  end

  ['invalid', ['invalid'], { enabled: 'true' }, { base_url: 'http://pbx.example.test' }].each_with_index do |payload, index|
    it "HTTP rejects invalid settings payload #{index + 1} without modifying storage" do
      original = integration.reload.attributes
      patch path, params: { settings: payload }, headers: root.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(integration.reload.attributes).to eq(original)
      expect(response.body.match?(/block2b-|Bearer/)).to be(false)
    end
  end

  context 'HTTP configuration authorization' do
    it 'allows a member SuperAdmin to read and update only the Account selected by the URL' do
      other = create(:telephony_integration, history_enabled: false, pabx_settings: settings)
      other_before = other.reload.attributes
      integration
      get path, headers: root.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.body.match?(/block2b-|Bearer/)).to be(false)
      patch path, params: { settings: settings.merge('timeout_seconds' => 12), account_id: other.account_id,
                            id: other.id, role: 'administrator', type: 'SuperAdmin' }, headers: root.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(integration.reload.pabx_settings['timeout_seconds']).to eq(12)
      expect(integration.account_id).to eq(account.id)
      expect(other.reload.attributes).to eq(other_before)
      expect(response.body.match?(/block2b-|Bearer/)).to be(false)
    end

    it 'cannot elevate an ordinary member through forged privilege or membership parameters' do
      user = create(:user, account: account, role: :agent)
      original = integration.reload.attributes
      user_before = user.reload.attributes
      membership_before = user.account_users.first.attributes
      patch path, params: { settings: settings, type: 'SuperAdmin', role: 'administrator',
                            user: { type: 'SuperAdmin' }, account_user: { role: 'administrator' } },
                  headers: user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(integration.reload.attributes).to eq(original)
      expect(user.reload.type).to eq(user_before['type'])
      expect(user.account_users.first.reload.attributes).to eq(membership_before)
      expect(response.body.match?(/block2b-|Bearer/)).to be(false)
    end
  end

  context 'HTTP diagnosis with authenticated simulated API' do
    before do
      integration.update!(pabx_settings: pabx_settings(sync_enabled: false))
      allow(Resolv).to receive(:getaddresses).with('pbx.example.test').and_return(['93.184.216.34'])
      stub_request(:post, 'https://pbx.example.test/api/v1/auth/login')
        .with(body: { email: 'block2b-user-a', password: 'block2b-secret-a' }.to_json)
        .to_return(body: { token: 'block2b-bearer' }.to_json)
    end

    it 'blocks dependent operations for expected tenant 8 and returned accountcode 12' do
      stub_request(:get, 'https://pbx.example.test/api/v1/admin/dashboard-extension')
        .with(headers: { Authorization: 'Bearer block2b-bearer' }).to_return(body: { accountcode: '12' }.to_json)
      post "#{path}/test_connection", headers: root.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('expected_tenant' => '8', 'returned_accountcode' => '12',
                                             'overall' => 'blocked_scope', 'error' => 'TENANT_MISMATCH')
      expect(integration.reload.pabx_settings['expected_tenant']).to eq('8')
      expect(integration.pabx_sync_state['diagnostic']['overall']).to eq('blocked_scope')
      expect(a_request(:any, %r{/ramais|/relatorio-cdr|/gravacoes})).not_to have_been_made
      get path, headers: root.create_new_auth_token
      expect(response.body.match?(/block2b-|Bearer/)).to be(false)
    end

    it 'returns a sanitized authentication failure without dependent requests' do
      stub_request(:post, 'https://pbx.example.test/api/v1/auth/login').to_return(status: 401)
      post "#{path}/test_connection", headers: root.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('overall' => 'not_verified', 'error' => 'INVALID_CREDENTIALS')
      expect(response.body.match?(/block2b-|Bearer/)).to be(false)
      expect(a_request(:get, %r{/api/v1/admin/})).not_to have_been_made
    end

    %w[FREE BUSY RINGING UNREGISTERED].each do |status|
      it "reads #{status} with the native collaborator of the current Account only" do
        own_user = create(:user, account: account, name: 'PABX Own Collaborator')
        create(:sip_credential, account: account, user: own_user, extension: '1410', username: '81410')
        foreign_account = create(:account)
        foreign_user = create(:user, account: foreign_account)
        create(:sip_credential, account: foreign_account, user: foreign_user, extension: '1410')
        stub_request(:get, 'https://pbx.example.test/api/v1/admin/dashboard-extension')
          .to_return(body: { accountcode: '8', statusMap: { '81410' => { status: status } } }.to_json)
        stub_request(:get, 'https://pbx.example.test/api/v1/admin/ramais').to_return(body: '[]')
        stub_request(:post, 'https://pbx.example.test/api/v1/admin/ramais/search')
          .with(body: { search: '1410' }.to_json).to_return(body: '[]')
        post "#{path}/test_connection", headers: root.create_new_auth_token
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body).to include('overall' => 'checks_passed', 'technical_extension' => '81410', 'technical_status' => status)
        expect(body.fetch('collaborators').pluck('user_id')).to eq([own_user.id])
        expect(response.body.match?(/block2b-|Bearer/)).to be(false)
        expect(a_request(:any, %r{/relatorio-cdr|/gravacoes})).not_to have_been_made
      end
    end
  end
end
