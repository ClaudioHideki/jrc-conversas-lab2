require 'rails_helper'

RSpec.describe 'Call History API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:service) { instance_double(Hodupbx::CallHistoryService, call: { count: 1, calls: calls }) }
  let(:calls) do
    [{ id: '1', direction: 'outbound', status: 'answered', external_number: '11999999999' }]
  end

  before do
    create(:telephony_integration, account: account)
    create(:sip_credential, account: account, user: agent)
    allow(Hodupbx::CallHistoryService).to receive(:new).and_return(service)
  end

  it 'uses the authenticated agent call-history extension, never the SIP username' do
    credential = account.sip_credentials.find_by!(user: agent)
    expect(credential.sip_username).to eq('10081110')
    expect(credential.extension).to eq('1110')
    expect(credential.call_history_extension).to eq('1110')

    get api_v1_account_call_history_url(account_id: account.id),
        params: { start_date: '2026-08-01', end_date: '2026-08-06' },
        headers: agent.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('extension' => '1110', 'count' => 1)
    expect(response.parsed_body['summary']).to eq(
      'total' => 1,
      'answered' => 1,
      'unanswered' => 0
    )
    expect(Hodupbx::CallHistoryService).to have_received(:new).with(hash_including(extension: '1110'))
  end

  it 'rejects periods longer than 31 days' do
    get api_v1_account_call_history_url(account_id: account.id),
        params: { start_date: '2026-06-01', end_date: '2026-08-06' },
        headers: agent.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('invalid_period')
  end

  it 'does not accept an extension override from the frontend' do
    get api_v1_account_call_history_url(account_id: account.id),
        params: { extension: '9999' },
        headers: agent.create_new_auth_token,
        as: :json

    expect(Hodupbx::CallHistoryService).to have_received(:new).with(hash_including(extension: '1110'))
  end

  it 'rejects another account before querying the telephony provider' do
    foreign_account = create(:account)
    get api_v1_account_call_history_url(account_id: foreign_account.id), headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(Hodupbx::CallHistoryService).not_to have_received(:new)
  end

  it 'does not borrow another operator extension when the authenticated operator has no configured credential' do
    other_agent = create(:user, account: account, role: :agent)
    get api_v1_account_call_history_url(account_id: account.id), headers: other_agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('configuration_missing')
    expect(Hodupbx::CallHistoryService).not_to have_received(:new)
  end

  it 'refuses reading or analyzing a call absent from the authenticated operator history' do
    allow(JrcVoiceQuality::SupabaseClient).to receive(:new).and_call_original
    allow(JrcVoiceQuality::Processor).to receive(:new).and_call_original
    path = "/api/v1/accounts/#{account.id}/call_quality_analyses"
    params = { call: { id: 'foreign-call', extension: '9999', recording_url: 'https://invalid.example/recording' } }
    get path, params: params, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    post path, params: params, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(Hodupbx::CallHistoryService).to have_received(:new).with(hash_including(extension: '1110')).twice
    expect(JrcVoiceQuality::SupabaseClient).not_to have_received(:new)
    expect(JrcVoiceQuality::Processor).not_to have_received(:new)
  end
end
