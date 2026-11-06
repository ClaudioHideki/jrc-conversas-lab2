require 'rails_helper'

RSpec.describe 'Atomic native proposal adjustments', :approval_core, :commercial_approvals, type: :request do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm']) }
  let(:manager) { approval_actor(scope, permissions: %w[jrc_approvals_decide jrc_approvals_adjust jrc_crm], role: :administrator) }
  let(:director) { approval_actor(scope, permissions: %w[jrc_approvals_decide jrc_crm]) }
  let(:proposal) do
    source = commercial_fixture(scope, author)[:proposal]
    source.update!(discount_cents: 300)
    source.recalculate_totals!
    source.reload
  end
  let(:definition) do
    base = approval_definition([manager])
    base['schema_version'] = 2
    base['steps'] << approval_definition([director])['steps'].first.merge('code' => 'director')
    base.merge('tiers' => { 'field' => 'total_cents', 'currency' => nil, 'min' => 0, 'max' => nil, 'coverage' => 'complete',
                            'rows' => [{ 'min' => 0, 'max' => 750, 'min_inclusive' => true, 'max_inclusive' => true, 'step_codes' => ['review'] },
                                       { 'min' => 750, 'max' => nil, 'min_inclusive' => false, 'max_inclusive' => false,
                                         'step_codes' => ['director'] }] })
  end
  let(:published) do
    proposal
    service = JrcApprovals::Policies.new(account: scope[:account], user: author.user)
    rule = service.create!(code: 'adjust-native', name: 'Synthetic adjustment', module_key: 'crm', event_key: 'proposal_send',
                           issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, definition: definition)
    service.validate!(policy_id: rule.id, expected_version: rule.lock_version)
    service.publish!(policy_id: rule.id, expected_version: rule.reload.lock_version)
  end
  let(:record) do
    published
    commercial_request(scope, author, proposal).first
  end
  let(:service) { JrcApprovals::Adjustments.new(account: scope[:account], user: manager.user) }
  let(:values) do
    { request_id: record.id, changes: { 'discount_cents' => 100 }, mode: 'save', reason: 'Synthetic permitted discount adjustment',
      expected_version: record.lock_version, idempotency_key: 'adjust-native-1' }
  end

  it 'persists a pending revision with unchanged provenance, old snapshots and native recalculation' do
    previous = record.attributes.slice('snapshot', 'stage_plan', 'fingerprint', 'requester_id', 'policy_version_id', 'expires_at')
    revised = service.call(**values)
    expect(proposal.reload.discount_cents).to eq(100)
    expect(revised).to have_attributes(state: 'pending', requester_id: author.id, policy_version_id: record.policy_version_id,
                                       expires_at: record.expires_at)
    expect(record.reload.state).to eq('stale')
    expect(record.attributes.slice(*previous.keys)).to eq(previous)
    expect(revised.snapshot.dig('values', 'total_cents')).to eq(700)
    audit = JrcApprovals::AuditEvent.find_by!(request_id: record.id, event_type: 'request_adjusted')
    expect(audit).to have_attributes(actor_id: manager.id, data: a_hash_including('before' => { 'discount_cents' => 300 },
                                                                                  'after' => { 'discount_cents' => 100 },
                                                                                  'revised_request_id' => revised.id))
    expect(proposal.events.last.user_id).to eq(manager.user_id)
  end

  it 'saves and approves through the native decision engine atomically' do
    revised = service.call(**values, mode: 'approve', step_code: 'review')
    expect(revised.state).to eq('approved')
    expect(revised.decisions.first).to have_attributes(actor_id: manager.id, principal_id: manager.id, decision: 'approved')
    expect(JrcApprovals::RequestVerification.approved?(revised, revised.policy_version, revised.snapshot)).to be(true)
  end

  it 'accepts the exact monetary equivalent of the Word25-to20-percent example without installing a percentage source field' do
    proposal.update!(discount_cents: 200)
    proposal.recalculate_totals!
    base = service.options(record).fetch(:maximum_discount_cents)
    expect(base).to eq(800)
    original = record.attributes.slice('snapshot', 'stage_plan', 'requester_id', 'policy_version_id')
    native = JrcCrm::CommercialFinancials.new(attributes: { products_cents: base, snapshot: { discount_percent: '20' } }, items: []).call
    expect(native.fetch(:discount_cents)).to eq(160)
    revised = service.call(**values, changes: { 'discount_cents' => native.fetch(:discount_cents) }, mode: 'approve', step_code: 'review')
    expect([proposal.reload.discount_cents, revised.state]).to eq([160, 'approved'])
    expect(record.reload.attributes.slice(*original.keys)).to eq(original)
    audit = JrcApprovals::AuditEvent.find_by!(request_id: record.id, event_type: 'request_adjusted')
    expect(audit.data).to include('before' => { 'discount_cents' => 200 }, 'after' => { 'discount_cents' => 160 }, 'mode' => 'approve')
    expect(JrcApprovals::RequestVerification.approved?(revised, revised.policy_version, revised.snapshot)).to be(true)
  end

  it 'persists the exact applied amount without changing native commercial terms or old approval snapshots' do
    proposal.update!(commercial_notes: 'Synthetic retained native term')
    terms = proposal.attributes.slice('commercial_notes', 'term_months', 'renewal_type')
    original = record.attributes.slice('snapshot', 'stage_plan', 'fingerprint', 'requester_id', 'policy_version_id')
    expect(service.options(record)).to include(maximum_discount_cents: 800)
    revised = service.call(**values)
    expect(proposal.reload.financial_summary).to include(discount_cents: 100, total_cents: 700)
    expect(proposal.attributes.slice(*terms.keys)).to eq(terms)
    expect(record.reload.attributes.slice(*original.keys)).to eq(original)
    expect(revised.snapshot.dig('values', 'total_cents')).to eq(700)
    audit = JrcApprovals::AuditEvent.find_by!(request_id: record.id, event_type: 'request_adjusted')
    expect(audit.data.fetch('before')).to eq('discount_cents' => 300)
  end

  it 'rejects a requested amount that native valuation would cap, without saving a false adjustment receipt' do
    input = values.merge(changes: { 'discount_cents' => 900 })
    before = [proposal.reload.attributes, record.reload.attributes, JrcApprovals::Request.count, JrcApprovals::AuditEvent.count,
              proposal.events.count]
    expect { service.call(**input) }.to raise_error(JrcApprovals::Error, 'INVALID_COMMERCIAL_TERMS')
    expect([proposal.reload.attributes, record.reload.attributes, JrcApprovals::Request.count,
            JrcApprovals::AuditEvent.count, proposal.events.count]).to eq(before)
  end

  it 'reports native valuation mismatch as an HTTP error and permits a valid retry without a false success receipt' do
    payload = values.except(:request_id).merge(changes: { discount_cents: 900 })
    before = [proposal.reload.attributes, record.reload.attributes]
    post "/api/v1/accounts/#{scope[:account].id}/approvals/requests/#{record.id}/adjust",
         params: { adjustment: payload }, headers: manager.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'INVALID_COMMERCIAL_TERMS')
    expect([proposal.reload.attributes, record.reload.attributes]).to eq(before)
    post "/api/v1/accounts/#{scope[:account].id}/approvals/requests/#{record.id}/adjust",
         params: { adjustment: payload.merge(changes: { discount_cents: 100 }) }, headers: manager.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('saved')).to be(true)
    expect(proposal.reload.financial_summary.fetch(:discount_cents)).to eq(100)
  end

  it 'rolls back the source, invalidations, revisions, audit and votes when the new tier needs another principal' do
    initial = values.merge(mode: 'approve', step_code: 'review', changes: { 'discount_cents' => 0 })
    before = [proposal.reload.attributes, record.reload.attributes, JrcApprovals::Request.count,
              JrcApprovals::AuditEvent.count, JrcApprovals::Decision.count, proposal.events.count]
    expect { service.call(**initial) }.to raise_error(JrcApprovals::Error, 'STEP_NOT_CURRENT')
    expect([proposal.reload.attributes, record.reload.attributes, JrcApprovals::Request.count,
            JrcApprovals::AuditEvent.count, JrcApprovals::Decision.count, proposal.events.count]).to eq(before)
  end

  it 'can save into another tier without approving it or disclosing its request through the HTTP receipt' do
    payload = values.except(:request_id).merge(changes: { discount_cents: 0 })
    post "/api/v1/accounts/#{scope[:account].id}/approvals/requests/#{record.id}/adjust",
         params: { adjustment: payload }, headers: manager.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('saved' => true, 'request' => nil)
    revised = JrcApprovals::Request.order(:id).last
    expect(revised.stage_plan.pluck('code')).to eq(['director'])
    expect(revised.decisions).to be_empty
  end

  it 'requires the explicit adjustment permission even for a native administrator' do
    input = values
    manager.update!(custom_role: nil)
    expect { service.call(**input) }.to raise_error(Pundit::NotAuthorizedError)
    expect(proposal.reload.discount_cents).to eq(300)
  end

  it 'does not convert an approval roster or adjust permission into native CRM edit access' do
    manager.update!(role: :agent)
    expect(service.options(record)).to be_nil
    expect { service.call(**values) }.to raise_error(Pundit::NotAuthorizedError)
    expect(proposal.reload.discount_cents).to eq(300)
  end

  it 'rejects foreign tenants before any native writes' do
    foreign = approval_scope
    actor = approval_actor(foreign, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm'], role: :administrator)
    expect { JrcApprovals::Adjustments.new(account: foreign[:account], user: actor.user).call(**values) }
      .to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'blocks stale versions and never edits a locked accepted proposal' do
    input = values
    expect { service.call(**input, expected_version: input[:expected_version] + 1) }
      .to raise_error(JrcApprovals::Error, 'VERSION_CONFLICT')
    proposal.update!(locked_at: Time.current)
    expect { service.call(**input) }.to raise_error(JrcApprovals::Error, 'SOURCE_LOCKED')
    expect(proposal.reload.discount_cents).to eq(300)
  end

  it 'rejects uninstalled fields and malformed values instead of granting arbitrary model updates' do
    input = values
    [{ 'owner_id' => manager.user_id }, { 'discount_percent' => 20 }, { 'discount_cents' => '100' }, { 'discount_cents' => -1 }].each do |changes|
      expect { service.call(**input, changes: changes) }.to raise_error(JrcApprovals::Error, 'INVALID_ADJUSTMENT_FIELDS')
    end
    expect(proposal.reload.discount_cents).to eq(300)
  end

  it 'replays without duplicate effects and rejects a changed reason or later source context' do
    input = values
    revised = service.call(**input)
    before = [JrcApprovals::Request.count, JrcApprovals::AuditEvent.count, proposal.events.count]
    expect(service.call(**input).id).to eq(revised.id)
    expect([JrcApprovals::Request.count, JrcApprovals::AuditEvent.count, proposal.events.count]).to eq(before)
    expect { service.call(**input, reason: 'Different intent') }.to raise_error(JrcApprovals::Error, 'IDEMPOTENCY_CONTENT_CONFLICT')
    JrcCrm::ProposalMutation.call!(proposal: proposal, actor: author.user, attributes: { discount_cents: 50 })
    expect { service.call(**input) }.to raise_error(JrcApprovals::Error, 'CONTEXT_STALE')
  end
end
