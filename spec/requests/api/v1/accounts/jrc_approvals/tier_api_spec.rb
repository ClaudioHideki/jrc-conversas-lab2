require 'rails_helper'

RSpec.describe 'Native commercial tier API', :approval_core, :commercial_approvals, type: :request do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm']) }
  let(:manager) { approval_actor(scope, permissions: %w[jrc_approvals_decide jrc_crm]) }
  let(:director) { approval_actor(scope, permissions: %w[jrc_approvals_decide jrc_crm]) }
  let(:fixture) { commercial_fixture(scope, author) }
  let(:proposal) { fixture[:proposal] }
  let(:headers) { author.user.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{scope[:account].id}/approvals" }
  let(:definition) do
    draft = approval_definition([manager])
    draft['schema_version'] = 2
    draft['steps'] << approval_definition([director])['steps'].first.merge('code' => 'director')
    draft.merge('tiers' => { 'field' => 'total_cents', 'currency' => nil, 'min' => 0, 'max' => nil, 'coverage' => 'complete',
                             'rows' => [{ 'min' => 0, 'max' => 750, 'min_inclusive' => true, 'max_inclusive' => true, 'step_codes' => ['review'] },
                                        { 'min' => 750, 'max' => nil, 'min_inclusive' => false, 'max_inclusive' => false,
                                          'step_codes' => ['director'] }] })
  end

  let(:values) do
    { name: 'Synthetic tiered CRM approval', module_key: 'crm', event_key: 'proposal_send', definition: definition,
      issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id }
  end
  let(:published) do
    proposal
    service = JrcApprovals::Policies.new(account: scope[:account], user: author.user)
    record = service.create!(**values, code: 'synthetic-tier-api')
    service.validate!(policy_id: record.id, expected_version: record.lock_version)
    service.publish!(policy_id: record.id, expected_version: record.reload.lock_version)
  end

  it 'persists, validates and publishes the same tier definition through the native HTTP lifecycle' do
    proposal
    post "#{url}/policies", params: { policy: values }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    policy = response.parsed_body
    expect(policy['draft_definition']).to eq(definition)
    post "#{url}/policies/#{policy['id']}/validate", params: { expected_version: policy['lock_version'] }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    validated = response.parsed_body
    post "#{url}/policies/#{policy['id']}/publish", params: { expected_version: validated['lock_version'] }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    record = JrcApprovals::Policy.find(policy['id'])
    expect(record.current_version.definition).to eq(definition)
  end

  it 'simulates without mutation and approves the real CRM source using the selected tier only' do
    published
    before = [JrcApprovals::Request.count, JrcApprovals::AuditEvent.count, proposal.reload.attributes]
    post "#{url}/requests/simulate", params: { key: 'crm.proposal_send', resource_id: proposal.id }, headers: headers, as: :json
    predicted = response.parsed_body
    expect(predicted).to include('effects' => [], 'predicted_state' => 'pending',
                                 'versions' => [a_hash_including('plan' => [a_hash_including('code' => 'director',
                                                                                             'principal_names' => [director.user.name])])])
    expect([JrcApprovals::Request.count, JrcApprovals::AuditEvent.count, proposal.reload.attributes]).to eq(before)
    post "#{url}/requests", params: { approval_request: { key: 'crm.proposal_send', resource_id: proposal.id, idempotency_key: 'tier-api-create' } },
                            headers: headers, as: :json
    expect(response).to have_http_status(:created)
    record = JrcApprovals::Request.find(response.parsed_body.first['id'])
    expect(record.stage_plan.pluck('code')).to eq(['director'])
    decision = { step_code: 'director', decision: 'approved', reason: 'Synthetic selected authority', expected_version: record.lock_version,
                 idempotency_key: 'tier-api-vote' }
    post "#{url}/requests/#{record.id}/decide", params: { decision: decision }, headers: director.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(record.decisions.first.principal_id).to eq(director.id)
    expect(JrcApprovals::RequestVerification.approved?(record.reload, record.policy_version, record.snapshot)).to be(true)
  end

  it 'keeps foreign tenant requests and unauthorized management unable to publish a tier policy' do
    proposal
    values = { name: 'Synthetic forbidden tier', module_key: 'crm', event_key: 'proposal_send', definition: definition,
               issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id }
    expect do
      post "#{url}/policies", params: { policy: values }, headers: director.user.create_new_auth_token, as: :json
    end.not_to change(JrcApprovals::Policy, :count)
    expect(response).to have_http_status(:unauthorized)
    other = approval_scope
    expect do
      post "/api/v1/accounts/#{other[:account].id}/approvals/policies", params: { policy: values }, headers: headers, as: :json
    end.not_to change(JrcApprovals::Policy, :count)
    expect(response).not_to have_http_status(:created)
  end
end
