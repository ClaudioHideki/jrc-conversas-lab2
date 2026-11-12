require 'rails_helper'

RSpec.describe 'Own delegations HTTP lifecycle', :approval_core, type: :request do
  let(:scope) { approval_scope }
  let(:principal) { approval_actor(scope, permissions: %w[jrc_approvals_delegate jrc_approvals_decide]) }
  let(:recipient) { approval_actor(scope, permissions: ['jrc_approvals_decide']) }
  let(:author) { approval_actor(scope) }
  let(:url) { "/api/v1/accounts/#{scope[:account].id}/approvals" }
  let(:input) do
    { delegate_id: recipient.id, issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, actions: ['approved'],
      reason: 'Synthetic own delegation HTTP', starts_at: 1.minute.ago.iso8601(6), ends_at: 1.hour.from_now.iso8601(6),
      idempotency_key: 'own-http-intent' }
  end
  let(:grant) do
    post "#{url}/own_delegations", params: { delegation: input }, headers: principal.user.create_new_auth_token, as: :json
    response.parsed_body
  end

  it 'creates without rule management, persists, lists only involved parties and revokes immutably' do
    id = grant.fetch('id')
    expect(response).to have_http_status(:created)
    get "#{url}/own_delegations", headers: recipient.user.create_new_auth_token, as: :json
    expect(response.parsed_body).to include(a_hash_including('id' => id, 'principal_name' => principal.user.name, 'can_revoke' => false))
    get "#{url}/own_delegations", headers: author.user.create_new_auth_token, as: :json
    expect(response.parsed_body).to include(a_hash_including('id' => id, 'can_revoke' => true))
    delete "#{url}/own_delegations/#{id}", headers: principal.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:no_content)
    expect(JrcApprovals::OwnDelegations.find!(scope[:account], id).revoked?).to be(true)
  end

  it 'applies the selected global grant through the real decision endpoint and records the principal' do
    id = grant.fetch('id')
    approval_publish(scope, author, approval_definition([principal]).merge('delegation_allowed' => true))
    request = approval_request(scope, author)
    get "#{url}/requests/#{request.id}", headers: recipient.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['allowed_decisions'].first['choices']).to include(a_hash_including('own_delegation_id' => id))
    post "#{url}/requests/#{request.id}/decide", params: { decision: { own_delegation_id: id, step_code: 'review', decision: 'approved',
                                                                       reason: 'Synthetic own HTTP vote', expected_version: 0,
                                                                       idempotency_key: 'own-http-vote' } },
                                                 headers: recipient.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(request.reload.state).to eq('approved')
    expect(request.decisions.first).to have_attributes(actor_id: recipient.id, principal_id: principal.id)
  end

  it 'only offers scoped eligible recipients with bounded pagination and no email or tokens' do
    recipient
    get "#{url}/own_delegations/recipients", params: { issuer_company_id: scope[:company].id,
                                                       business_unit_id: scope[:unit].id, per_page: 1 },
                                             headers: principal.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([{ 'id' => recipient.id, 'name' => recipient.user.name }])
    expect(response.headers['X-Per-Page']).to eq('1')
    get "#{url}/own_delegations/recipients", params: { issuer_company_id: scope[:company].id,
                                                       business_unit_id: scope[:unit].id, per_page: 101 },
                                             headers: principal.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'denies another principal, another account and a foreign issuer without altering grants' do
    id = grant.fetch('id')
    delete "#{url}/own_delegations/#{id}", headers: recipient.user.create_new_auth_token, as: :json
    expect(response).not_to have_http_status(:no_content)
    other = approval_scope
    post "/api/v1/accounts/#{other[:account].id}/approvals/own_delegations", params: { delegation: input },
                                                                             headers: principal.user.create_new_auth_token, as: :json
    expect(response).not_to have_http_status(:created)
    post "#{url}/own_delegations", params: { delegation: input.merge(issuer_company_id: other[:company].id,
                                                                     business_unit_id: other[:unit].id,
                                                                     idempotency_key: 'foreign-scope') },
                                   headers: principal.user.create_new_auth_token, as: :json
    expect(response).not_to have_http_status(:created)
    expect(JrcApprovals::OwnDelegations.grants(scope[:account]).size).to eq(1)
  end

  it 'requires an explicit timezone offset instead of interpreting an ambiguous local API timestamp' do
    post "#{url}/own_delegations", params: { delegation: input.merge(starts_at: '2050-01-01T09:00:00') },
      headers: principal.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'INVALID_DELEGATION_WINDOW')
    expect(JrcApprovals::OwnDelegations.grants(scope[:account])).to be_empty
  end
end
