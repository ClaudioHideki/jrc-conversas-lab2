require 'rails_helper'

RSpec.describe 'Deferred operator pause API', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:headers) { actor.create_new_auth_token }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/deferred_pause_request" }
  let(:state) { JrcContactCenter::AgentStateSnapshot.new(account_user: member) }
  let(:values) do
    { command_id: SecureRandom.uuid, expected_state_version: state.version, reason_code: 'lunch',
      expected_request_revision: JrcContactCenter::DeferredPauseRevision.token(account: account, member: member) }
  end
  let(:request_record) { JrcContactCenter::DeferredPauseManager.new(account: account, member: member).request!(values) }

  before { account.enable_features!('jrc_contact_center') }

  include_context 'a native pending voice ACW for deferred pause'

  it 'persists and recovers one own pending request without fabricating a paused state or provider ACK' do
    post endpoint, headers: headers, params: { deferred_pause_request: values }, as: :json
    expect(response).to have_http_status(:success)
    body = response.parsed_body.fetch('item')
    expect(body.fetch('deferred_pause_request')).to include('request_id' => values[:command_id], 'state' => 'pending', 'local_only' => true)
    expect(body.fetch('state')).to eq('acw')
    expect(body.fetch('provider_confirmed')).to be(false)
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/agent_state", headers: headers
    expect(response.parsed_body.dig('item', 'deferred_pause_request', 'request_id')).to eq(values[:command_id])
    expect(JrcContactCenter::AgentStateEvent.where(account: account, state: 'paused')).to be_empty
  end

  it 'does not accept account, member, actor or unit authority from the request body' do
    post endpoint, headers: headers, params: { deferred_pause_request: values.merge(unit_id: 999) }, as: :json
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.fetch('error')).to eq('invalid_deferred_pause')
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
  end

  it 'rejects explicit malformed private values rather than dropping them through strong parameters' do
    post endpoint, headers: headers, params: { deferred_pause_request: values.merge(justification: []) }, as: :json
    expect(response).to have_http_status(:bad_request)
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
  end

  it 'rejects a stale state revision before writing the intent or audit' do
    post endpoint, headers: headers, params: { deferred_pause_request: values.merge(expected_state_version: '999999') }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('state_conflict')
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
  end

  it 'keeps requests private from another operator in the same account and refuses cancellation' do
    request_record
    other = create(:user, :contact_center_eligible, account: account, role: :agent)
    other_headers = other.create_new_auth_token
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/agent_state", headers: other_headers
    expect(response).to have_http_status(:success)
    expect(response.parsed_body.fetch('item')).not_to have_key('deferred_pause_request')
    delete endpoint, headers: other_headers, params: { request_id: request_record.request_id }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(request_record.reload.state).to eq('pending')
  end

  it 'refuses another account even when the request UUID is known' do
    request_record
    other_account = create(:account)
    other_account.enable_features!('jrc_contact_center')
    other = create(:user, :contact_center_eligible, account: other_account, role: :agent)
    delete "/api/v1/accounts/#{other_account.id}/jrc_contact_center/deferred_pause_request", headers: other.create_new_auth_token,
                                                                                       params: { request_id: request_record.request_id }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(request_record.reload.state).to eq('pending')
  end

  it 'does not expose pending private data or permit writes after operating eligibility is revoked' do
    request_record
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    delete endpoint, headers: headers, params: { request_id: request_record.request_id }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(request_record.reload.state).to eq('pending')
  end

  it 'cancels only the identified own request and preserves the historical receipt' do
    delete endpoint, headers: headers, params: { request_id: request_record.request_id }, as: :json
    expect(response).to have_http_status(:success)
    expect(request_record.reload.state).to eq('cancelled')
    expect(response.parsed_body.fetch('item')).not_to have_key('deferred_pause_request')
    expect(request_record.finished_at).to be_present
  end

  it 'does not deserialize an HTTP body into the trusted internal transition reference' do
    request_record
    body = { state: 'paused', command_id: "deferred-pause:#{request_record.request_id}", reason_code: 'lunch',
             expected_state_version: state.version, deferred_request: { id: request_record.id } }
    patch "/api/v1/accounts/#{account.id}/jrc_contact_center/agent_state", headers: headers, params: { agent_state: body }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('pause_request_exists')
    expect(request_record.reload.state).to eq('pending')
    expect(JrcContactCenter::AgentStateEvent.where(account: account, state: 'paused')).to be_empty
  end

  it 'redacts the complete private request envelope through native log filtering' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    text = filter.filter('deferred_pause_request' => values.merge(justification: 'SYNTHETIC never log')).to_json
    expect(text).not_to include('SYNTHETIC never log')
    expect(text).to include('[FILTERED]')
  end
end
