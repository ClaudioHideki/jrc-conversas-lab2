require 'rails_helper'

RSpec.describe 'Native PABX settings and history API', :pabx, type: :request do
  let(:account) { create(:account) }
  let(:root) { create(:super_admin) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}" }
  let(:integration) { create(:telephony_integration, account: account, pabx_settings: pabx_settings, pabx_username: 'synthetic-user', pabx_password: 'synthetic-password') }
  before { create(:account_user, account: account, user: root, role: :administrator) }

  it 'does not create integration, company, unit or SIP credentials on a settings read' do
    expect { get "#{base}/telephony_integration", headers: root.create_new_auth_token }.not_to change(TelephonyIntegration, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('configured' => false, 'settings' => {})
    expect(account.sip_credentials).to be_empty
  end

  it 'keeps administrative writes and diagnostics exclusive to the native Super Admin' do
    admin = create(:user, account: account, role: :administrator)
    [admin, agent].each do |user|
      patch "#{base}/telephony_integration", params: { settings: pabx_settings }, headers: user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{base}/telephony_integration/test_connection", headers: user.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
    end
    expect(account.reload.telephony_integration).to be_nil
  end

  it 'stores credentials encrypted, preserves blank values and never returns them after storage' do
    patch "#{base}/telephony_integration", params: { settings: pabx_settings(enabled: false), api_username: 'synthetic-user',
      api_password: 'synthetic-password' }, headers: root.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    row = account.reload.telephony_integration
    expect(row.pabx_password).to eq('synthetic-password')
    expect(row.pabx_password_before_type_cast).not_to include('synthetic-password')
    expect(response.body).not_to include('synthetic-user', 'synthetic-password')
    patch "#{base}/telephony_integration", params: { settings: pabx_settings(enabled: false), api_username: '', api_password: '' },
      headers: root.create_new_auth_token, as: :json
    expect(row.reload.pabx_password).to eq('synthetic-password')
  end

  it 'does not authenticate, enqueue sync or alter SIP just by saving' do
    allow(Pabx::Client).to receive(:new)
    credential = create(:sip_credential, account: account, user: agent)
    before = credential.attributes
    integration
    expect do
      patch "#{base}/telephony_integration", params: { settings: pabx_settings(enabled: false) }, headers: root.create_new_auth_token, as: :json
    end.not_to have_enqueued_job(Pabx::SyncJob)
    expect(Pabx::Client).not_to have_received(:new)
    expect(credential.reload.attributes).to eq(before)
  end

  it 'does not allow a root session to borrow a configuration from another Account without its native membership' do
    foreign = create(:account)
    get "/api/v1/accounts/#{foreign.id}/telephony_integration", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns only the authenticated operator extension and current tenant from persisted history' do
    integration
    create(:sip_credential, account: account, user: agent, call_history_extension: '1410')
    attributes = Pabx::Contract.new(Pabx::Settings.new(integration)).normalize(pabx_row).merge(provider: 'pabx_v1', synced_at: Time.current)
    allowed = TelephonyCallRecord.create!(attributes.merge(account: account, external_tenant: '8'))
    TelephonyCallRecord.create!(attributes.merge(account: account, external_tenant: '12'))
    TelephonyCallRecord.create!(attributes.merge(account: account, external_tenant: '8', extension: '9999', external_unique_id: 'other-extension'))
    TelephonyCallRecord.create!(attributes.merge(account: create(:account), external_tenant: '8'))
    get "#{base}/call_history", params: { extension: '9999' }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['calls'].pluck('id')).to eq([allowed.id])
    expect(response.body).not_to include('recording_reference', '/var/spool', 'synthetic-password')
  end

  it 'requires authorized call ownership before any recording request' do
    integration
    create(:sip_credential, account: account, user: agent, call_history_extension: '1410')
    record = TelephonyCallRecord.create!(account: account, provider: 'pabx_v1', external_tenant: '8', external_unique_id: 'hidden',
      extension: '9999', synced_at: Time.current, has_recording: true)
    allow(Pabx::Provider).to receive(:new)
    get "#{base}/call_history/#{record.id}/recording", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(Pabx::Provider).not_to have_received(:new)
  end

  it 'proxies a recording using the authorized saved call rather than a browser path' do
    integration
    integration.update!(pabx_settings: pabx_settings(recording_lookup: 'link'))
    create(:sip_credential, account: account, user: agent, call_history_extension: '1410')
    record = TelephonyCallRecord.create!(account: account, provider: 'pabx_v1', external_tenant: '8', external_unique_id: 'visible',
      extension: '1410', synced_at: Time.current, has_recording: true, recording_reference: '/var/spool/asterisk/monitor/8/synthetic.wav')
    provider = instance_double(Pabx::Provider, recording: { body: 'synthetic-audio', content_type: 'audio/wav' })
    allow(Pabx::Provider).to receive(:new).and_return(provider)
    get "#{base}/call_history/#{record.id}/recording", params: { path: '../../etc/passwd' }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq('synthetic-audio')
    expect(provider).to have_received(:recording).with(record)
  end
end
