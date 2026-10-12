require 'rails_helper'

RSpec.describe 'E4 bounded visual administration', :approval_core, :commercial_approvals,
               type: :request do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm'], role: :administrator) }
  let(:approver) { approval_actor(scope, permissions: %w[jrc_approvals_decide jrc_crm]) }
  let(:fixture) { commercial_fixture(scope, author) }
  let(:proposal) { fixture[:proposal] }
  let(:url) { "/api/v1/accounts/#{scope[:account].id}/approvals" }
  let(:headers) { author.user.create_new_auth_token }

  it 'projects current scope capabilities without granting native administrators decide' do
    native = create(:user, account: scope[:account], role: :administrator)
    JrcCrm::UserBusinessUnit.create!(
      account: scope[:account], user: native, company: scope[:company], business_unit: scope[:unit],
      scope: 'BUSINESS_UNIT', structure_managed: true, active: true
    )
    get "#{url}/context", headers: native.create_new_auth_token
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['account_id']).to eq(scope[:account].id)
    expect(body['scopes'].first['capabilities']).to include('policy_manage', 'view_audit')
    expect(body['scopes'].first['capabilities']).not_to include('decide')
  end

  it 'does not project unauthorized scopes or permit editor identity enumeration to reviewers' do
    proposal
    get "#{url}/context", headers: approver.user.create_new_auth_token
    expect(response.parsed_body['scopes'].map { |row| row['business_unit_id'] }).to eq([scope[:unit].id])
    expect(response.parsed_body['scopes'].first['capabilities']).to eq(['decide'])
    get "#{url}/options", params: { issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id },
                          headers: approver.user.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'uses native scoped identities and excludes foreign tenant members' do
    proposal
    other = approval_scope
    foreign = approval_actor(other)
    approver
    get "#{url}/options", params: { issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['account_users'].map { |row| row['id'] }).to include(author.id, approver.id)
    expect(response.parsed_body['account_users'].map { |row| row['id'] }).not_to include(foreign.id)
    expect(response.body).not_to include('email', 'password', 'token')
    get "#{url}/options", params: { issuer_company_id: other[:company].id, business_unit_id: other[:unit].id }, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'lists authorized native resources with no financial snapshot and denies foreign resources' do
    proposal
    get "#{url}/resources", params: { key: 'crm.proposal_send' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.first).to include('id' => proposal.id, 'label' => proposal.title)
    expect(response.body).not_to include('snapshot', 'minimum_price', 'price_reference', 'token')
    get "#{url}/resources", params: { key: 'crm.price_exception' }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'shows bounded request identity, stages and history but never the internal roster or source snapshot' do
    commercial_policy(scope, author, [approver])
    record = commercial_request(scope, author, proposal).first
    approval_vote(scope, approver, record)
    get "#{url}/requests/#{record.id}", headers: headers
    body = response.parsed_body
    expect(body).to include('requester_name' => author.user.name, 'policy_version' => 1, 'state' => 'approved')
    expect(body['stages'].first).to include('code' => 'review', 'quorum' => 1, 'approved_count' => 1)
    expect(body['decisions'].first).to include('actor_name' => approver.user.name, 'decision' => 'approved')
    expect(body['allowed_decisions']).to eq([])
    expect(body.keys).not_to include('snapshot', 'stage_plan', 'financials', 'evidence_digest')
    expect(response.body).not_to include('principal_ids', 'minimum_price_cents')
  end

  it 'separates requested and actionable inbox records including current delegated choices' do
    definition = approval_definition([approver]).merge('delegation_allowed' => true)
    policy = JrcApprovals::Policies.new(
      account: scope[:account], user: author.user
    ).create!(code: 'delegated', name: 'Synthetic delegation',
              module_key: 'crm', event_key: 'proposal_send', issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id,
              definition: definition)
    fixture
    manager = JrcApprovals::Policies.new(
      account: scope[:account], user: author.user
    )
    manager.validate!(policy_id: policy.id, expected_version: policy.lock_version)
    manager.publish!(policy_id: policy.id, expected_version: policy.reload.lock_version)
    record = commercial_request(scope, author, proposal).first
    delegate = approval_actor(scope, permissions: %w[jrc_approvals_decide jrc_crm])
    grant = JrcApprovals::Delegations.new(
      account: scope[:account], user: author.user
    ).create!(policy_version_id: policy.reload.current_version_id,
              step_code: 'review', principal_id: approver.id, delegate_id: delegate.id, actions: ['approved'], reason: 'Synthetic window',
              starts_at: 1.minute.ago, ends_at: 1.hour.from_now)
    get "#{url}/requests", params: { assigned_to_me: 'true' }, headers: delegate.user.create_new_auth_token
    expect(response.parsed_body.map { |row| row['id'] }).to eq([record.id])
    get "#{url}/requests", params: { requested_by_me: 'true' }, headers: delegate.user.create_new_auth_token
    expect(response.parsed_body).to eq([])
    get "#{url}/delegations", headers: headers
    expect(response.parsed_body.first).to include('id' => grant.id, 'principal_name' => approver.user.name, 'delegate_name' => delegate.user.name,
                                                  'window_state' => 'active')
    delete "#{url}/delegations/#{grant.id}", headers: headers
    expect(response).to have_http_status(:no_content)
    expect(grant.reload.revoked_at).to be_present
    get "#{url}/delegations", headers: headers
    expect(response.parsed_body.first).to include('window_state' => 'revoked')
    get "#{url}/requests", params: { assigned_to_me: 'true' }, headers: delegate.user.create_new_auth_token
    expect(response.parsed_body).to eq([])
  end

  it 'returns validated eligible counts and immutable published version authors' do
    proposal
    values = { code: 'visual', name: 'Synthetic UI policy', module_key: 'crm', event_key: 'proposal_send',
               issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, definition: approval_definition([approver]) }
    post "#{url}/policies", params: { policy: values }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    policy = response.parsed_body
    post "#{url}/policies/#{policy['id']}/validate", params: { expected_version: policy['lock_version'] }, headers: headers, as: :json
    expect(response.parsed_body['validation_plan'].first).to include('code' => 'review', 'eligible_count' => 1, 'quorum' => 1)
    policy = response.parsed_body
    post "#{url}/policies/#{policy['id']}/publish", params: { expected_version: policy['lock_version'] }, headers: headers, as: :json
    expect(response.parsed_body['current_version']).to eq(1)
    get "#{url}/policies/#{policy['id']}/versions", headers: headers
    expect(response.parsed_body.first['publisher_name']).to eq(author.user.name)
  end

  it 'enriches simulator presentation without executing any effect' do
    commercial_policy(scope, author, [approver])
    proposal
    before = [JrcApprovals::Request.count, JrcApprovals::Decision.count, JrcApprovals::AuditEvent.count,
              JrcCrm::SalesOrder.count, Message.count, JrcCrm::Contract.count, proposal.reload.attributes]
    post "#{url}/requests/simulate", params: { key: 'crm.proposal_send', resource_id: proposal.id }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['effects']).to eq([])
    expect(response.parsed_body['versions'].first).to include('priority' => 10, 'selection_mode' => 'exclusive')
    expect([JrcApprovals::Request.count, JrcApprovals::Decision.count, JrcApprovals::AuditEvent.count,
            JrcCrm::SalesOrder.count, Message.count, JrcCrm::Contract.count, proposal.reload.attributes]).to eq(before)
  end

  it 'denies absent capabilities, foreign accounts, forced approval and edits to source evidence' do
    commercial_policy(scope, author, [approver])
    record = commercial_request(scope, author, proposal).first
    nobody = approval_actor(scope, permissions: ['jrc_crm'])
    get "#{url}/context", headers: nobody.user.create_new_auth_token
    expect(response.parsed_body['scopes']).to eq([])
    get "#{url}/requests/#{record.id}", headers: nobody.user.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    spoofed = { step_code: 'review', decision: 'approved', reason: 'Spoofed', expected_version: 0,
                idempotency_key: 'spoof', actor_id: approver.id, evidence_digest: 'a' * 64 }
    post "#{url}/requests/#{record.id}/decide", params: { decision: spoofed }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized).or have_http_status(:unprocessable_entity)
    expect(record.reload.state).to eq('pending')
    other = approval_scope
    get "/api/v1/accounts/#{other[:account].id}/approvals/requests/#{record.id}", headers: headers
    expect(response).not_to have_http_status(:ok)
  end
end
