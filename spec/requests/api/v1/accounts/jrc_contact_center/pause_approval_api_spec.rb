require 'rails_helper'

RSpec.describe 'Native mandatory pause approval API', :approval_core, type: :request do
  include_context 'with all-scope native pause approval'

  let(:headers) { actor.create_new_auth_token }

  def endpoint
    "/api/v1/accounts/#{account.id}/jrc_contact_center/deferred_pause_request"
  end

  it 'returns a no-store complete preview without creating an operational intent or a native approval' do
    post "#{endpoint}/preview", headers: headers, params: { deferred_pause_request: values.merge(queue_id: queues.first.id.to_s) }, as: :json
    expect(response).to have_http_status(:success)
    expect(response.headers.fetch('Cache-Control')).to include('no-store')
    expect(response.parsed_body.fetch('account_user_id')).to eq(member.id.to_s)
    preview = response.parsed_body.fetch('preview')
    expect(preview.fetch('required')).to be(true)
    expect(preview.fetch('payload').fetch('coverage').fetch('groups').size).to eq(2)
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
    expect(pause_requests).to be_empty
  end

  it 'requires the reviewed server digest and rejects supplied scope authority before creating anything' do
    post endpoint, headers: headers, params: { deferred_pause_request: values }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('pause_approval_review_required')
    post "#{endpoint}/preview", headers: headers, params: { deferred_pause_request: values.merge(unit_ids: [units.first.id]) }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('invalid_deferred_pause')
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
  end

  it 'persists and recovers the pending all-scope state through authenticated native APIs without applying it early' do
    publish_all_pause_policies
    preview = JrcContactCenter::PauseApprovalIntent.new(context: pause_context).call(values)
    post endpoint, headers: headers, params: { deferred_pause_request: values, expected_approval_digest: preview.fetch('digest') }, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body.dig('receipt', 'state')).to eq('pending')
    expect(response.parsed_body.dig('item', 'deferred_pause_request', 'approval', 'status')).to eq('approval_required')
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/agent_state", headers: headers
    expect(response.parsed_body.dig('item', 'deferred_pause_request', 'request_id')).to eq(values.fetch(:command_id))
    expect(response.parsed_body.dig('item', 'deferred_pause_request', 'approval', 'scopes').size).to eq(2)
    expect(JrcContactCenter::AgentStateEvent.where(account: account, state: 'paused')).to be_empty
    expect(pause_requests.size).to eq(2)
  end

  it 'returns a complete creation conflict without any partial durable state when a corporate policy is missing' do
    publish_pause_policy(0)
    preview = JrcContactCenter::PauseApprovalIntent.new(context: pause_context).call(values)
    post endpoint, headers: headers, params: { deferred_pause_request: values, expected_approval_digest: preview.fetch('digest') }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('pause_approval_policy_missing')
    expect(pause_requests).to be_empty
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
    expect(JrcContactCenter::PauseApprovalReview.where(account: account)).to be_empty
  end

  it 'does not let the direct agent-state API bypass a mandatory approval' do
    body = { state: 'paused', command_id: SecureRandom.uuid, expected_state_version: '0', reason_code: definition.fetch('code') }
    patch "/api/v1/accounts/#{account.id}/jrc_contact_center/agent_state", headers: headers, params: { agent_state: body }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('pause_approval_required')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'applies once after both actual Central decisions and recovers the paused state after a separate authenticated reload' do
    publish_all_pause_policies
    row = create_reviewed_pause
    approve_pause_requests
    body = { deferred_pause_request: { request_id: row.request_id, expected_state_version: values.fetch(:expected_state_version) } }
    2.times { post "#{endpoint}/apply", headers: headers, params: body, as: :json }
    expect(response).to have_http_status(:success)
    expect(response.parsed_body.dig('receipt', 'state')).to eq('applied')
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/agent_state", headers: headers
    expect(response.parsed_body.dig('item', 'state')).to eq('paused')
    expect(response.parsed_body.dig('item', 'provider_confirmed')).to be(false)
    expect(response.parsed_body.fetch('item')).not_to have_key('deferred_pause_request')
    expect(JrcContactCenter::AgentStateEvent.where(account: account, state: 'paused').count).to eq(1)
  end

  it 'rejects incomplete or forged apply documents without raising a Ruby missing-keyword error' do
    [{ request_id: SecureRandom.uuid }, { request_id: SecureRandom.uuid, expected_state_version: '0', unit_id: units.first.id }].each do |document|
      post "#{endpoint}/apply", headers: headers, params: { deferred_pause_request: document }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('error')).to eq('invalid_deferred_pause')
    end
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'denies another operator the known UUID even if they can operate in their own native account' do
    publish_all_pause_policies
    row = create_reviewed_pause
    other = create(:user, :contact_center_eligible, account: account, role: :agent)
    body = { deferred_pause_request: { request_id: row.request_id, expected_state_version: '0' } }
    post "#{endpoint}/apply", headers: other.create_new_auth_token, params: body, as: :json
    expect(response).to have_http_status(:not_found)
    expect(row.reload.state).to eq('pending')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'denies a reused preview after operating eligibility is revoked and exposes no stored impact' do
    headers
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    post "#{endpoint}/preview", headers: headers, params: { deferred_pause_request: values }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).not_to have_key('preview')
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
  end
end
