require 'rails_helper'

RSpec.describe 'Approval workspace authorized indicators and search', type: :request, approval_core: true do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope) }
  let(:approver) { approval_actor(scope) }
  let(:policy) { approval_publish(scope, author, approval_definition([approver])) }
  let(:approval) { policy; approval_request(scope, author) }
  let(:url) { "/api/v1/accounts/#{scope[:account].id}/approvals/requests" }
  let(:headers) { author.user.create_new_auth_token }

  it 'counts authorized pending requests independently of the list state and pagination' do
    approval
    get "#{url}/summary", params: { state: 'approved', page: 20, per_page: 1, time_zone: 'America/Sao_Paulo' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('pending' => 1, 'approved' => 0, 'rejected' => 0)
    expect(response.parsed_body['time_zone']).to eq('America/Sao_Paulo')
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body.keys).not_to include('snapshot', 'financials', 'stage_plan')
  end

  it 'counts completed decisions in the current month without exposing their contents' do
    approval_vote(scope, approver, approval)
    get "#{url}/summary", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('pending' => 0, 'approved' => 1, 'rejected' => 0)
    expect(response.parsed_body.keys).not_to include('reason', 'decisions')
  end

  it 'does not expose another account through request filters or indicators' do
    approval
    other = approval_scope
    outsider = approval_actor(other)
    get "/api/v1/accounts/#{other[:account].id}/approvals/requests/summary",
        params: { issuer_company_id: scope[:company].id }, headers: outsider.user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('pending' => 0, 'approved' => 0, 'rejected' => 0, 'due_today' => 0)
  end

  it 'requires an authenticated account member for indicators' do
    get "#{url}/summary"
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not count requests outside the members native business-unit coverage' do
    approval
    other = approval_scope(account: scope[:account])
    outsider = approval_actor(other, permissions: %w[jrc_approvals_view_audit])
    get "#{url}/summary", params: { issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id },
                            headers: outsider.user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('pending' => 0, 'approved' => 0, 'rejected' => 0)
  end

  it 'does not count approvals after the feature is disabled' do
    approval
    scope[:account].disable_features!('jrc_approvals')
    get "#{url}/summary", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects invalid time zones rather than returning an invented reporting period' do
    get "#{url}/summary", params: { time_zone: 'unconfigured-zone' }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'searches policy names with literal wildcard characters and retains native pagination' do
    approval
    get url, params: { q: policy.name, order: 'recent', page: 1, per_page: 1 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.pluck('id')).to eq([approval.id])
    get url, params: { q: '%_' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([])
  end

  it 'rejects unsupported sort orders and oversized search inputs' do
    get url, params: { order: 'arbitrary-sql' }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    get url, params: { q: 'x' * 201 }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
