require 'rails_helper'

RSpec.describe 'Approval core authenticated API', type: :request, approval_core: true do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope) }
  let(:approver) { approval_actor(scope) }
  let(:policy) { approval_publish(scope, author, approval_definition([approver])) }
  let(:request) { policy; approval_request(scope, author) }
  let(:url) { "/api/v1/accounts/#{scope[:account].id}/approvals" }

  it 'requires authentication and feature activation' do
    get "#{url}/requests/#{request.id}"
    expect(response).to have_http_status(:unauthorized)
    scope[:account].disable_features!('jrc_approvals')
    get "#{url}/requests/#{request.id}", headers: author.user.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body['error']).to eq('You are not authorized to do this action')
  end

  it 'never serializes snapshots, internal financials, tokens or eligibility details by default' do
    get "#{url}/requests/#{request.id}", headers: author.user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['id']).to eq(request.id)
    expect(response.parsed_body.keys).not_to include('snapshot', 'financials', 'stage_plan', 'request_key', 'input_digest')
  end

  it 'denies cross-tenant request, policy publication and decision attempts' do
    other = approval_scope
    outsider = approval_actor(other, role: :administrator)
    other_url = "/api/v1/accounts/#{other[:account].id}/approvals"
    get "#{other_url}/requests/#{request.id}", headers: outsider.user.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    post "#{other_url}/policies/#{policy.id}/publish", params: { expected_version: policy.lock_version },
      headers: outsider.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{other_url}/requests/#{request.id}/decide", params: { decision: { step_code: 'review', decision: 'approved',
      reason: 'Cross-tenant attempt', expected_version: 0, idempotency_key: 'cross' } }, headers: outsider.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'ignores spoofed account, approval roster and financial authorization from the client' do
    policy
    post "#{url}/requests", params: { approval_request: { key: 'synthetic.review', resource_id: scope[:unit].id,
      idempotency_key: 'server-only', account_id: 999, approvers: [author.id], minimum_price: 0, evaluated: 'approved', snapshot: {} } },
      headers: author.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    record = JrcApprovals::Request.find(response.parsed_body.first['id'])
    expect(record.account_id).to eq(scope[:account].id)
    expect(record.stage_plan.first['principal_ids']).to eq([approver.id])
    expect(record.state).to eq('pending')
    expect(record.snapshot.dig('values', 'amount', 'amount_cents')).to eq(2000)
  end

  it 'preserves 409 expected-version and idempotency-content conflicts' do
    fields = { step_code: 'review', decision: 'approved', reason: 'Synthetic evidence', expected_version: 99, idempotency_key: 'once' }
    post "#{url}/requests/#{request.id}/decide", params: { decision: fields }, headers: approver.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:conflict)
    fields[:expected_version] = 0
    post "#{url}/requests/#{request.id}/decide", params: { decision: fields }, headers: approver.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    fields[:reason] = 'Changed content'
    post "#{url}/requests/#{request.id}/decide", params: { decision: fields }, headers: approver.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:conflict)
    expect(request.decisions.count).to eq(1)
  end

  it 'protects the audit endpoint with its own permission and unit scope' do
    get "#{url}/requests/#{request.id}/audit", headers: author.user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.first['event_type']).to eq('request_created')
    limited = approval_actor(scope, permissions: ['jrc_approvals_request_create'])
    get "#{url}/requests/#{request.id}/audit", headers: limited.user.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body['error']).to eq('You are not authorized to do this action')
  end

  it 'does not list data from unauthorized units in the same tenant' do
    request
    other_scope = approval_scope(account: scope[:account])
    outsider = approval_actor(other_scope)
    get "#{url}/requests", headers: outsider.user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([])
    get "#{url}/policies", headers: outsider.user.create_new_auth_token
    expect(response.parsed_body).to eq([])
  end

  it 'publishes only complete synthetic drafts through existing account authentication' do
    values = { code: 'api-test', name: 'Synthetic API', module_key: 'synthetic', event_key: 'review',
      issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, definition: approval_definition([approver]) }
    post "#{url}/policies", params: { policy: values }, headers: author.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body['id']
    expect(response.parsed_body['enabled']).to be(false)
    post "#{url}/policies/#{id}/validate", params: { expected_version: 0 }, headers: author.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    post "#{url}/policies/#{id}/publish", params: { expected_version: 1 }, headers: author.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['enabled']).to be(true)
  end

  it 'blocks incomplete authenticated input without creating a policy or decision' do
    post "#{url}/policies", params: { policy: { name: 'Incomplete' } }, headers: author.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('INVALID_INPUT')
    expect(JrcApprovals::Policy.where(account_id: scope[:account].id).count).to eq(0)
  end
end
