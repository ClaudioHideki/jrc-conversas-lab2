require 'rails_helper'

RSpec.describe 'Configured native financial changes', :approval_core, :commercial_approvals, type: :request do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm']) }
  let(:reviewer) { approval_actor(scope, permissions: %w[jrc_approvals_decide jrc_approvals_adjust jrc_crm], role: :administrator) }
  let(:fixture) { commercial_fixture(scope, author) }
  let(:proposal) { fixture[:proposal] }
  let(:definition) do
    approval_definition([reviewer]).merge('condition' => { 'field' => 'total_cents', 'op' => 'gte', 'value' => 0 },
      'adjustments' => { 'schema_version' => 1, 'fields' => { 'first_billing_days' => { 'min' => 0, 'max' => 90 } } },
      'review_directions' => { 'actions' => ['request_adjustment'], 'escalation_policy_id' => nil })
  end
  let(:policy) do
    proposal
    service = JrcApprovals::Policies.new(account: scope[:account], user: author.user)
    rule = service.create!(code: 'synthetic-financial-terms', name: 'Synthetic financial terms', module_key: 'crm', event_key: 'proposal_terms',
      issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, definition: definition)
    service.validate!(policy_id: rule.id, expected_version: rule.lock_version)
    service.publish!(policy_id: rule.id, expected_version: rule.reload.lock_version)
  end
  let(:record) do
    policy
    JrcApprovals::Requests.new(account: scope[:account], user: author.user)
      .create!(key: 'crm.proposal_terms', resource_id: proposal.id, idempotency_key: 'synthetic-financial-request').first
  end
  let(:changes) { { 'first_billing_days' => proposal.first_billing_days == 30 ? 45 : 30 } }
  let(:service) { JrcApprovals::Adjustments.new(account: scope[:account], user: reviewer.user) }
  let(:input) { { request_id: record.id, changes: changes, mode: 'save', reason: 'Synthetic financial correction',
    expected_version: record.lock_version, idempotency_key: 'synthetic-financial-save' } }

  it 'uses configured financial fields without changing the original captured snapshot' do
    original = record.snapshot.deep_dup
    revised = service.call(**input)
    expect(proposal.reload.first_billing_days).to eq(changes['first_billing_days'])
    expect(revised.state).to eq('pending')
    expect(record.reload.snapshot).to eq(original)
    expect(revised.requester_id).to eq(record.requester_id)
  end

  it 'rejects a change beyond the configured adjustment limit without persisting a partial change' do
    values = input.merge(changes: { 'first_billing_days' => 91 })
    before = [proposal.reload.attributes, JrcApprovals::Request.count, JrcApprovals::AuditEvent.count]
    expect { service.call(**values) }.to raise_error(JrcApprovals::Error)
    expect([proposal.reload.attributes, JrcApprovals::Request.count, JrcApprovals::AuditEvent.count]).to eq(before)
  end

  it 'refuses a commercial price or product change through a financial request' do
    expect { service.call(**input.merge(changes: { 'discount_cents' => 100 })) }.to raise_error(JrcApprovals::Error)
    expect { service.call(**input.merge(changes: { 'product_id' => 1 })) }.to raise_error(JrcApprovals::Error)
  end

  it 'replays the same exact adjustment without another review or event' do
    values = input
    revised = service.call(**values)
    counts = [JrcApprovals::Request.count, JrcApprovals::AuditEvent.count]
    expect(service.call(**values).id).to eq(revised.id)
    expect([JrcApprovals::Request.count, JrcApprovals::AuditEvent.count]).to eq(counts)
  end

  it 'records a correction request without editing the financial source' do
    before = proposal.attributes
    result = JrcApprovals::ReviewDirections.new(account: scope[:account], user: reviewer.user).call(request_id: record.id,
      kind: 'request_adjustment', text: 'Explain and revise the synthetic terms', expected_version: record.lock_version,
      idempotency_key: 'synthetic-return-direction', step_code: 'review')
    expect(result).to include(recorded: true, source_changed: false)
    expect(record.reload.state).to eq('returned')
    expect(proposal.reload.attributes).to eq(before)
  end

  it 'never escalates to a user-supplied or unconfigured policy' do
    expect do
      JrcApprovals::ReviewDirections.new(account: scope[:account], user: reviewer.user).call(request_id: record.id,
        kind: 'escalate', text: 'Unconfigured route', expected_version: record.lock_version,
        idempotency_key: 'synthetic-no-route', step_code: 'review')
    end.to raise_error(JrcApprovals::Error)
    expect(record.reload.state).to eq('pending')
  end
end
