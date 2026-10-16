require 'rails_helper'

RSpec.describe 'PABX stored CDR HTTP scope', :pabx, type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:integration) do
    create(:telephony_integration, account: account, pabx_settings: pabx_settings(sync_enabled: false),
           pabx_username: 'synthetic-user', pabx_password: 'synthetic-password')
  end
  let(:path) { "/api/v1/accounts/#{account.id}/call_history" }
  let(:attributes) do
    Pabx::Contract.new(Pabx::Settings.new(integration)).normalize(pabx_row)
      .merge(account: account, provider: 'pabx_v1', external_tenant: '8', synced_at: Time.current)
  end
  before do
    integration
    create(:sip_credential, account: account, user: user, extension: '1410', call_history_extension: '1410')
    expect(Pabx::Client).not_to receive(:new)
  end

  it 'shows only the authorized personal extension and current Account and tenant' do
    allowed = TelephonyCallRecord.create!(attributes)
    TelephonyCallRecord.create!(attributes.merge(account: create(:account)))
    TelephonyCallRecord.create!(attributes.merge(external_tenant: '12'))
    TelephonyCallRecord.create!(attributes.merge(extension: '9999', external_unique_id: 'other-extension'))
    get path, params: { extension: '9999' }, headers: user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['calls'].pluck('id')).to eq([allowed.id])
    expect(response.body).not_to include('recording_reference', 'pabx_password')
  end

  it 'filters inbound missed calls without treating outbound unanswered calls as missed' do
    missed = TelephonyCallRecord.create!(attributes.merge(direction: 'inbound', status: 'unanswered'))
    TelephonyCallRecord.create!(attributes.merge(external_unique_id: 'outgoing', direction: 'outbound', status: 'unanswered'))
    get path, params: { status: 'missed' }, headers: user.create_new_auth_token
    expect(response.parsed_body['calls'].pluck('id')).to eq([missed.id])
    expect(response.parsed_body['calls'].first['missed']).to be(true)
  end

  it 'uses requested display-zone calendar boundaries and stable pagination' do
    first = TelephonyCallRecord.create!(attributes.merge(started_at: '2026-10-15T02:59:00Z'))
    later = TelephonyCallRecord.create!(attributes.merge(external_unique_id: 'later', started_at: '2026-10-15T03:01:00Z'))
    get path, params: { start_date: '2026-10-15', end_date: '2026-10-15', time_zone: 'America/Sao_Paulo', per_page: 1 },
              headers: user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['calls'].pluck('id')).to eq([later.id])
    expect(response.parsed_body['calls'].pluck('id')).not_to include(first.id)
  end

  [{ last_error: 'TENANT_MISMATCH' }, { diagnostic: { tenant_compatible: false } }].each do |state|
    it "blocks cached calls after an explicit tenant mismatch #{state.keys.first}" do
      TelephonyCallRecord.create!(attributes)
      integration.update!(pabx_sync_state: state)
      get path, headers: user.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('TENANT_MISMATCH')
      expect(response.parsed_body).not_to have_key('calls')
    end
  end

  it 'rejects a session from another Account' do
    foreign = create(:user, account: create(:account))
    get path, headers: foreign.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'validates invalid periods without returning cached data' do
    get path, params: { start_date: '2026-10-16', end_date: '2026-10-15' }, headers: user.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
