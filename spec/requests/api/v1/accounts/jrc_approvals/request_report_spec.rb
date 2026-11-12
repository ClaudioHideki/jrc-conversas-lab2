require 'rails_helper'

RSpec.describe 'Native detailed approval report', :approval_core, :commercial_approvals, type: :request do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm'], role: :administrator) }
  let(:reviewer) { approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm'], role: :administrator) }
  let(:director) { approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm']) }
  let(:proposal) { commercial_fixture(scope, author)[:proposal] }
  let(:definition) do
    base = approval_definition([reviewer])
    base['schema_version'] = 2
    base['delegation_allowed'] = true
    base['steps'] << approval_definition([director])['steps'].first.merge('code' => 'director')
    base.merge('tiers' => { 'field' => 'total_cents', 'currency' => nil, 'min' => 0, 'max' => nil, 'coverage' => 'complete',
                            'rows' => [{ 'min' => 0, 'max' => 1000, 'min_inclusive' => true, 'max_inclusive' => true, 'step_codes' => ['review'] },
                                       { 'min' => 1000, 'max' => nil, 'min_inclusive' => false, 'max_inclusive' => false,
                                         'step_codes' => ['director'] }] })
  end
  let(:policies) { JrcApprovals::Policies.new(account: scope[:account], user: author.user) }
  let(:version) do
    proposal
    policy = policies.create!(code: 'report-native', name: 'Synthetic report rule', module_key: 'crm', event_key: 'proposal_send',
                              issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, definition: definition)
    policies.validate!(policy_id: policy.id, expected_version: policy.lock_version)
    policies.publish!(policy_id: policy.id, expected_version: policy.reload.lock_version)
    policy.reload.current_version
  end
  let(:record) do
    version
    commercial_request(scope, author, proposal).first
  end
  let(:url) { "/api/v1/accounts/#{scope[:account].id}/approvals/requests/#{record.id}/report" }
  let(:headers) { author.user.create_new_auth_token }
  let(:reporter) { JrcApprovals::RequestReport.new(account: scope[:account], user: author.user) }

  it 'reports captured tiers and actual votes without replacing the old rule after a new publication' do
    vote = approval_vote(scope, reviewer, record)
    old = record.reload.attributes.deep_dup
    policy = version.policy.reload
    policies.edit!(policy_id: policy.id, expected_version: policy.lock_version, name: 'Synthetic revised policy',
                   definition: definition.merge('expires_in_seconds' => 7200))
    policies.validate!(policy_id: policy.id, expected_version: policy.reload.lock_version)
    policies.publish!(policy_id: policy.id, expected_version: policy.reload.lock_version)
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    report = response.parsed_body
    expect(report).to include('captured_plan' => record.stage_plan, 'captured_values' => a_hash_including('total_cents' => 800),
                              'captured_rule' => a_hash_including('id' => version.id, 'digest' => version.digest, 'definition' => definition))
    expect(report['decisions']).to include(a_hash_including('id' => vote.id, 'actor_id' => reviewer.id, 'principal_id' => reviewer.id))
    expect(response.headers).to include('cache-control' => 'no-store', 'x-content-type-options' => 'nosniff')
    expect(record.reload.attributes).to eq(old)
    event = JrcApprovals::AuditEvent.find_by!(request_id: record.id, event_type: 'request_report_accessed')
    expect(event.data['sha256']).to eq(Digest::SHA256.hexdigest(response.body))
  end

  it 'retains the actual delegation used at the vote after it has been revoked' do
    target = record
    grants = JrcApprovals::Delegations.new(account: scope[:account], user: author.user)
    grant = grants.create!(policy_version_id: version.id, step_code: 'review', principal_id: reviewer.id, delegate_id: director.id,
                           actions: ['approved'], reason: 'Synthetic delegation', starts_at: 1.minute.ago, ends_at: 1.hour.from_now)
    vote = approval_vote(scope, director, target, delegation_id: grant.id)
    grants.revoke!(id: grant.id)
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expected = { 'id' => vote.id, 'actor_id' => director.id, 'principal_id' => reviewer.id,
                 'delegation' => a_hash_including('id' => grant.id, 'revoked_at' => grant.reload.revoked_at.iso8601(3)) }
    expect(response.parsed_body['decisions']).to include(a_hash_including(expected))
    expect(vote.reload.delegation_id).to eq(grant.id)
  end

  it 'links the native adjustment revision and original immutable request without carrying its votes' do
    target = record
    revised = JrcApprovals::Adjustments.new(account: scope[:account], user: reviewer.user).call(
      request_id: target.id, changes: { 'discount_cents' => 100 }, mode: 'save', reason: 'Synthetic price correction',
      expected_version: target.lock_version, idempotency_key: 'report-adjustment'
    )
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    report = response.parsed_body
    expect(report['revisions']).to contain_exactly(a_hash_including('id' => target.id, 'state' => 'stale'),
                                                   a_hash_including('id' => revised.id, 'state' => 'pending'))
    expect(report['events']).to include(a_hash_including('event_type' => 'request_adjusted',
                                                         'data' => a_hash_including('revised_request_id' => revised.id,
                                                                                    'after' => { 'discount_cents' => 100 })))
    expect(JSON.parse(reporter.call(revised.id))['revisions'].pluck('id')).to contain_exactly(target.id, revised.id)
    expect(revised.decisions).to be_empty
  end

  it 'does not turn decision or requester access into audit permission' do
    target = record
    limited = approval_actor(scope, permissions: %w[jrc_approvals_request_create jrc_approvals_decide jrc_crm])
    get "/api/v1/accounts/#{scope[:account].id}/approvals/requests/#{target.id}/report", headers: limited.user.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    reviewer.update!(custom_role: create(:custom_role, account: scope[:account], permissions: %w[jrc_approvals_decide jrc_crm]), role: :agent)
    get url, headers: reviewer.user.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect(JrcApprovals::AuditEvent.where(request_id: target.id, event_type: 'request_report_accessed')).to be_empty
  end

  it 'rejects another tenant and revocation of the native unit grant' do
    target = record
    foreign = approval_scope
    outsider = approval_actor(foreign)
    get url, headers: outsider.user.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    JrcCrm::UserBusinessUnit.find_by!(account_id: scope[:account].id, user_id: author.user_id).update!(active: false)
    get url, headers: headers, params: { user_id: author.user_id, business_unit_id: scope[:unit].id }
    expect(response).to have_http_status(:unauthorized)
    expect(JrcApprovals::AuditEvent.where(request_id: target.id, event_type: 'request_report_accessed')).to be_empty
  end

  it 'omits unrecognized audit payloads and transport or storage secrets' do
    target = record
    JrcApprovals::Ledger.audit!(account: scope[:account], actor: author, event: 'synthetic_private_observation', key: 'report-private-data',
                                request_id: target.id, data: { state: 'pending', credential: 'SYNTHETIC-PRIVATE-CREDENTIAL',
                                                               source_snapshot: { content: 'SYNTHETIC-PRIVATE-SNAPSHOT' } })
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.body).not_to include('SYNTHETIC-PRIVATE', 'idempotency_key', 'payload_digest', 'correlation_key', 'source_snapshot')
    expect(response.parsed_body['events']).to include(a_hash_including('event_type' => 'synthetic_private_observation',
                                                                       'data' => { 'state' => 'pending' }))
  end

  it 'fails closed if audit permission is revoked during projection and records no successful export' do
    target = record
    allow(JrcApprovals::RequestSerializer).to receive(:new).and_wrap_original do |original, *args|
      author.update!(custom_role: create(:custom_role, account: scope[:account], permissions: ['jrc_approvals_request_create']))
      original.call(*args)
    end
    expect { reporter.call(target.id) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcApprovals::AuditEvent.where(request_id: target.id, event_type: 'request_report_accessed')).to be_empty
  end

  it 'rejects oversized reports without silent truncation or a success audit' do
    target = record
    stub_const('JrcApprovals::RequestReport::MAX_ROWS', 0)
    get url, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('REPORT_TOO_LARGE')
    expect(JrcApprovals::AuditEvent.where(request_id: target.id, event_type: 'request_report_accessed')).to be_empty
  end

  it 'preserves the global own-delegation binding actually used even after its grant is revoked' do
    target = record
    service = JrcApprovals::OwnDelegations.new(account: scope[:account], user: reviewer.user)
    grant = service.create!(delegate_id: director.id, issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id,
                            actions: ['approved'], starts_at: 1.minute.ago, ends_at: 1.hour.from_now,
                            idempotency_key: 'report-own-delegation', reason: 'Synthetic own delegation')
    vote = approval_vote(scope, director, target, own_delegation_id: grant.id)
    service.revoke!(id: grant.id)
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    binding = a_hash_including('id' => vote.delegation_id, 'own_delegation_id' => grant.id,
                               'own_grant' => a_hash_including('revocation' => a_hash_including('actor_id' => reviewer.id)))
    expect(response.parsed_body['decisions']).to include(a_hash_including('actor_id' => director.id, 'principal_id' => reviewer.id,
                                                                          'delegation' => binding))
    expect(grant.active?).to be(false)
  end

  context 'with a native v1 rule' do
    let(:definition) { approval_definition([reviewer]) }

    it 'exports the unchanged v1 rule without manufacturing tiers or revising its captured plan' do
      before = record.attributes.deep_dup
      get url, headers: headers
      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body.dig('captured_rule', 'definition')).to eq(definition)
      expect(response.parsed_body['captured_plan']).to eq(record.stage_plan)
      expect(record.reload.attributes).to eq(before)
    end
  end

  it 'reads the captured historical rule and values without consulting a replaced live adapter' do
    target = record
    expect(JrcApprovals::Catalog).not_to receive(:fetch)
    report = JSON.parse(reporter.call(target.id))
    expect(report['captured_values']).to include('total_cents' => 800)
    expect(report['captured_rule']['definition']).to eq(definition)
  end
end
