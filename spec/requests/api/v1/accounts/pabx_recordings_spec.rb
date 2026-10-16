require 'rails_helper'

RSpec.describe 'PABX private recording requests', :pabx, type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:integration) do
    create(:telephony_integration, account: account, pabx_settings: pabx_settings(recording_lookup: 'link', sync_enabled: false),
           pabx_username: 'synthetic-user', pabx_password: 'synthetic-password')
  end
  let(:record) do
    TelephonyCallRecord.create!(account: account, provider: 'pabx_v1', external_tenant: '8', extension: '1410',
                               external_unique_id: 'synthetic-http-recording', synced_at: Time.current, has_recording: true,
                               recording_reference: '/var/spool/asterisk/monitor/8/synthetic.wav')
  end
  let(:path) { "/api/v1/accounts/#{account.id}/call_history/#{record.id}/recording" }
  let(:audio) { 'RIFF'.b + [36].pack('V') + 'WAVEfmt '.b + [16, 1, 1, 8000, 16000, 2, 16].pack('VvvVVvv') + 'data'.b + [0].pack('V') }
  before do
    integration
    create(:sip_credential, account: account, user: user, extension: '1410', call_history_extension: '1410')
    allow(Resolv).to receive(:getaddresses).with('pbx.example.test').and_return(['93.184.216.34'])
    stub_request(:post, 'https://pbx.example.test/api/v1/auth/login').to_return(body: { token: 'synthetic-token' }.to_json)
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/dashboard-extension').to_return(body: { accountcode: '8' }.to_json)
    stub_request(:post, 'https://pbx.example.test/api/v1/admin/relatorio-cdr/download')
      .with(body: { link: '/var/spool/asterisk/monitor/8/synthetic.wav' }.to_json)
      .to_return(body: audio, headers: { 'Content-Type' => 'audio/wav' })
  end

  it 'proxies only the authorized stored recording and prevents public caching' do
    get path, params: { path: 'http://169.254.169.254/latest', link: '/etc/passwd' }, headers: user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.body.b).to eq(audio)
    expect(response.headers['Cache-Control']).to include('no-store', 'private')
    expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
    expect(response.headers.to_json).not_to include('synthetic-token', '/var/spool', 'synthetic-password')
  end

  it 'exposes only local recording eligibility metadata without connecting or returning a public URL' do
    expect(Pabx::Client).not_to receive(:new)
    get "#{path}_metadata", headers: user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('id' => record.id, 'has_recording' => true, 'recording_state' => 'requestable')
    expect(response.body).not_to include('/var/spool', 'http', 'synthetic-token')
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'rejects another Account and another operator before accessing the provider' do
    foreign = create(:user, account: create(:account))
    other = create(:user, account: account)
    create(:sip_credential, account: account, user: other, extension: '9999', call_history_extension: '9999')
    expect(Pabx::Client).not_to receive(:new)
    get path, headers: foreign.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    get path, headers: other.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects an unauthenticated recording request' do
    expect(Pabx::Client).not_to receive(:new)
    get path
    expect(response).to have_http_status(:unauthorized)
  end

  it 'keeps unconfirmed lookup mappings safely pending' do
    integration.update!(pabx_settings: pabx_settings(recording_lookup: 'uniqueId', sync_enabled: false))
    get path, headers: user.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('RECORDING_MAPPING_PENDING')
    expect(a_request(:post, %r{/relatorio-cdr/download})).not_to have_been_made
  end

  [403, 404, 410].each do |status|
    it "returns safe upstream unavailability HTTP #{status}" do
      stub_request(:post, 'https://pbx.example.test/api/v1/admin/relatorio-cdr/download')
        .to_return(status: status, body: 'synthetic-token synthetic-password')
      get path, headers: user.create_new_auth_token
      expect(response.status).to eq(status)
      expect(response.body).not_to include('synthetic-token', 'synthetic-password', '/var/spool')
    end
  end

  it 'blocks an explicitly mismatched tenant without downloading cached references' do
    integration.update!(pabx_sync_state: { diagnostic: { tenant_compatible: false } })
    expect(Pabx::Client).not_to receive(:new)
    get path, headers: user.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('TENANT_MISMATCH')
  end
end
