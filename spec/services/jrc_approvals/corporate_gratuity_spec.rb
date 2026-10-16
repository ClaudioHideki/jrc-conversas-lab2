require 'rails_helper'

RSpec.describe 'Corporate commercial gratuity', :approval_core, :commercial_approvals,
               type: :model do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm'], role: :administrator) }
  let(:jose) { approval_actor(scope, permissions: %w[jrc_approvals_decide jrc_crm]) }
  let(:karen) { approval_actor(scope, permissions: %w[jrc_approvals_decide jrc_crm]) }
  let(:thiago) { approval_actor(scope, permissions: %w[jrc_approvals_decide jrc_crm]) }
  let(:patricia) { approval_actor(scope, permissions: %w[jrc_approvals_decide jrc_crm]) }
  let(:fixture) { commercial_fixture(scope, author, discount: 0) }
  let(:proposal) { fixture[:proposal] }
  let(:item) { proposal.proposal_items.first }
  let(:manager) { JrcApprovals::Policies.new(account: scope[:account], user: author.user) }
  let(:gate) { JrcApprovals::CommercialGate.new(account: scope[:account], user: author.user) }
  let(:definition) do
    approval_definition([jose]).merge(
      'condition' => { 'field' => 'has_commercial_gratuity', 'op' => 'eq', 'value' => true },
      'reopen_mode' => 'restart_all', 'delegation_allowed' => true,
      'steps' => [jose, karen].each_with_index.map do |member, index|
        approval_definition([member], mode: 'all')['steps'].first.merge('code' => JrcApprovals::GratuityAuthorities::STEPS.keys[index])
      end
    )
  end
  let(:policy) do
    draft = manager.create!(code: SecureRandom.hex(6), name: 'Synthetic gratuity draft', module_key: 'crm', event_key: 'gratuity_request',
                            issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, definition: definition)
    manager.validate!(policy_id: draft.id, expected_version: draft.lock_version)
    manager.publish!(policy_id: draft.id, expected_version: draft.reload.lock_version)
  end

  before do
    scope[:company].update!(custom_attributes: { JrcCrm::CorporateProfile::KEY => {
                              'commercial_gratuity_principal_id' => jose.id, 'commercial_gratuity_substitute_id' => thiago.id,
                              'financial_gratuity_principal_id' => karen.id, 'financial_gratuity_substitute_id' => patricia.id,
                              'authorization_reference' => 'Synthetic managerial identity confirmation'
                            } })
    fixture[:product].update!(unit_price_cents: 100_000, minimum_price_cents: 90_000, setup_fee_cents: 20_000, billing_model: 'monthly')
    item.update!(unit_price_cents: 100_000, billing_model: 'monthly', setup_fee_cents: 0)
  end

  it 'detects free setup in a paid 1000 monthly proposal without replacing financial valuation' do
    before = proposal.financial_summary
    result = JrcApprovals::CommercialGratuity.new(resource: proposal).call
    expect(result).to include(has_commercial_gratuity: true, gratuity_item_count: 1, gratuity_type: ['installation'],
                              gratuity_total_cents: 20_000, approval_context_version: 1)
    expect(proposal.financial_summary).to eq(before)
    expect(before[:total_cents]).to eq(100_000)
  end

  it 'detects a free monthly line' do
    item.update!(discount_cents: 100_000, setup_fee_cents: 20_000)
    expect(JrcApprovals::CommercialGratuity.new(resource: proposal).call).to include(gratuity_type: ['monthly_fee'], gratuity_total_cents: 100_000)
  end

  %w[product service benefit promotion bonus].each do |kind|
    it "calculates explicit #{kind} among paid items" do
      item.update!(setup_fee_cents: 20_000)
      free = proposal.proposal_items.create!(product: fixture[:product], name_snapshot: 'Synthetic free line', quantity: 2,
                                             unit_price_cents: 0, setup_fee_cents: 20_000, billing_model: 'monthly', unit_name: 'unidade',
                                             commercial_gratuity: { type: kind, reason: 'Synthetic commercial benefit' })
      result = JrcApprovals::CommercialGratuity.new(resource: proposal.reload).call
      expect(result).to include(has_commercial_gratuity: true, gratuity_item_count: 1, gratuity_type: [kind], gratuity_total_cents: 200_000)
      expect(free.reload.commercial_gratuity['type']).to eq(kind)
    end
  end

  it 'does not classify an ordinary partial discount as gratuity' do
    item.update!(setup_fee_cents: 20_000, discount_cents: 1000)
    expect(JrcApprovals::CommercialGratuity.new(resource: proposal).call).to include(has_commercial_gratuity: false, discount_percentage: '1.0')
  end

  it 'does not infer a commercial gift from a technical zero without a paid native reference' do
    fixture[:product].update!(unit_price_cents: 0, minimum_price_cents: 0, setup_fee_cents: 0)
    item.reload.update!(unit_price_cents: 0)
    expect(JrcApprovals::CommercialGratuity.new(resource: proposal).call[:has_commercial_gratuity]).to be(false)
  end

  it 'keeps an explicit gift with unknown reference value pending' do
    fixture[:product].update!(unit_price_cents: 0, minimum_price_cents: 0, setup_fee_cents: 0)
    item.update!(unit_price_cents: 0, commercial_gratuity: { type: 'benefit', reason: 'Synthetic explicit benefit' })
    expect(JrcApprovals::CommercialGratuity.new(resource: proposal).call).to include(has_commercial_gratuity: true, gratuity_value_status: 'pending')
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)[:status]).to eq('PRICE_CONTEXT_PENDING')
    expect(gate.evaluate(key: 'crm.proposal_gratuity', resource_id: proposal.id)[:status]).to eq('GRATUITY_VALUE_PENDING')
  end

  it 'preserves the price v1 fields and distinguishes evaluated from permission to deliver' do
    old = JrcApprovals::Catalog.snapshot(account: scope[:account], user: author.user, key: 'crm.proposal_send', resource_id: proposal.id)
    expect(old['values'].keys.sort).to eq(JrcApprovals::CommercialCatalog::FIELDS.keys.sort)
    expect(old['values']['price_status']).to eq('evaluated')
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)).to include(required: true, status: 'POLICY_REQUIRED')
  end

  it 'leaves the policy as an unpublished draft until explicitly validated and published in disposable tests' do
    draft = manager.create!(code: 'gratuity_draft', name: 'Synthetic draft', module_key: 'crm', event_key: 'gratuity_request',
                            issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, definition: definition)
    expect(draft).to have_attributes(state: 'draft', enabled: false, current_version_id: nil)
  end

  it 'refuses incomplete authorities and incomplete sequence at validation/publication' do
    definition['steps'].pop
    draft = manager.create!(code: 'incomplete', name: 'Incomplete synthetic draft', module_key: 'crm', event_key: 'gratuity_request',
                            issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, definition: definition)
    expect do
      manager.validate!(policy_id: draft.id, expected_version: draft.lock_version)
    end.to raise_error(JrcApprovals::Error, 'INVALID_GRATUITY_SEQUENCE')
    expect { manager.publish!(policy_id: draft.id, expected_version: draft.lock_version) }.to raise_error(JrcApprovals::Error, 'POLICY_NOT_VALIDATED')
    expect(draft.reload).not_to be_enabled
  end

  it 'keeps the operation blocked after Jose, until Karen approves' do
    policy
    record = commercial_request(scope, author, proposal).first
    expect { approval_vote(scope, karen, record, step_code: 'gratuidade_financeira') }.to raise_error(JrcApprovals::Error, 'STEP_NOT_CURRENT')
    approval_vote(scope, jose, record, step_code: 'gratuidade_comercial')
    expect(record.reload.state).to eq('pending')
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)[:status]).to eq('APPROVAL_REQUIRED')
    approval_vote(scope, karen, record, step_code: 'gratuidade_financeira')
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)[:status]).to eq('ready')
    expect(proposal.reload.status).to eq('draft')
    expect(Message.where(account: scope[:account]).count).to eq(0)
  end

  it 'refuses an ineligible voter even with native administrator status and coverage' do
    policy
    record = commercial_request(scope, author, proposal).first
    expect { approval_vote(scope, author, record, step_code: 'gratuidade_comercial') }.to raise_error(Pundit::NotAuthorizedError)
    expect(record.reload.decisions.count).to eq(0)
  end

  it 'prevents self approval by a configured principal' do
    policy
    proposal.update!(owner: jose.user)
    jose.custom_role.update!(permissions: %w[jrc_crm jrc_approvals_decide jrc_approvals_request_create])
    expect { commercial_request(scope, jose, proposal) }.to raise_error(JrcApprovals::Error, 'INSUFFICIENT_APPROVERS')
    expect(JrcApprovals::Request.where(account: scope[:account]).count).to eq(0)
  end

  it 'keeps returned distinct from approved and requires a rejection reason' do
    policy
    record = commercial_request(scope, author, proposal).first
    expect { approval_vote(scope, jose, record, step_code: 'gratuidade_comercial', decision: 'rejected', reason: '') }
      .to raise_error(JrcApprovals::Error, 'REASON_REQUIRED')
    approval_vote(scope, jose, record, step_code: 'gratuidade_comercial', decision: 'returned')
    expect(record.reload.state).to eq('returned')
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)[:status]).to eq('APPROVAL_REQUIRED')
  end

  it 'does not duplicate a request or a vote, and rejects a new vote for a completed step' do
    policy
    record = commercial_request(scope, author, proposal, idempotency_key: 'same-gratuity').first
    expect(commercial_request(scope, author, proposal, idempotency_key: 'same-gratuity').map(&:id)).to eq([record.id])
    version = record.lock_version
    vote = approval_vote(scope, jose, record, step_code: 'gratuidade_comercial', expected_version: version, idempotency_key: 'same-vote')
    replay = approval_vote(scope, jose, record, step_code: 'gratuidade_comercial', expected_version: version, idempotency_key: 'same-vote')
    expect(replay.id).to eq(vote.id)
    expect { approval_vote(scope, jose, record, step_code: 'gratuidade_comercial') }.to raise_error(JrcApprovals::Error)
    expect(record.decisions.count).to eq(1)
  end

  it 'invalidates material changes without removing the approved commercial vote or audit' do
    policy
    record = commercial_request(scope, author, proposal).first
    approval_vote(scope, jose, record, step_code: 'gratuidade_comercial')
    item.update!(quantity: 2)
    JrcApprovals::CommercialInvalidation.call(resource: proposal.reload, user: author.user)
    expect(record.reload.state).to eq('stale')
    expect(record.decisions.count).to eq(1)
    expect(JrcApprovals::AuditEvent.where(request_id: record.id, event_type: 'request_invalidate').count).to eq(1)
  end

  it 'does not let an exclusive price policy replace the independent gratuity sequence' do
    item.update!(discount_cents: 20_000)
    commercial_policy(scope, author, [jose])
    policy
    records = commercial_request(scope, author, proposal, idempotency_key: 'price-and-gratuity')
    expect(records.map(&:event_key).sort).to eq(%w[proposal_gratuity proposal_send])
    approval_vote(scope, jose, records.find { |record| record.event_key == 'proposal_send' })
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)[:status]).to eq('APPROVAL_REQUIRED')
    expect(commercial_request(scope, author, proposal, idempotency_key: 'price-and-gratuity').map(&:id)).to eq(records.map(&:id))
  end

  it 'requires a formal absence, a named substitute, reason and validity for delegation' do
    version = policy.current_version
    delegations = JrcApprovals::Delegations.new(account: scope[:account], user: author.user)
    attrs = { policy_version_id: version.id, step_code: 'gratuidade_comercial', principal_id: jose.id, delegate_id: thiago.id,
              actions: ['approved'], reason: 'Synthetic leave', starts_at: 1.minute.ago, ends_at: 1.hour.from_now }
    expect { delegations.create!(**attrs) }.to raise_error(JrcApprovals::Error, 'GRATUITY_ABSENCE_AUTHORIZATION_REQUIRED')
    expect { delegations.create!(**attrs, delegate_id: patricia.id, absence_authorization: 'Synthetic leave authorization') }
      .to raise_error(JrcApprovals::Error, 'GRATUITY_ABSENCE_AUTHORIZATION_REQUIRED')
    grant = delegations.create!(**attrs, absence_authorization: 'Synthetic leave authorization')
    record = commercial_request(scope, author, proposal).first
    approval_vote(scope, thiago, record, step_code: 'gratuidade_comercial', delegation_id: grant.id)
    expect(record.reload.state).to eq('pending')
    expect(record.decisions.first.principal_id).to eq(jose.id)
  end

  it 'rejects cross-company policy selection even with explicit group coverage' do
    policy
    JrcCrm::UserBusinessUnit.create!(account: scope[:account], user: author.user, scope: 'GROUP', structure_managed: true)
    another = approval_scope(account: scope[:account])
    foreign = commercial_fixture(another, author, discount: 0)
    foreign[:product].update!(setup_fee_cents: 1000)
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: foreign[:proposal].id)[:status]).to eq('POLICY_REQUIRED')
    expect { commercial_request(scope, author, foreign[:proposal]) }.to raise_error(JrcApprovals::Error, 'POLICY_REQUIRED')
    expect(JrcApprovals::Request.where(account: scope[:account]).count).to eq(0)
  end

  it 'makes prior approval stale after authority configuration changes' do
    policy
    record = commercial_request(scope, author, proposal).first
    approval_vote(scope, jose, record, step_code: 'gratuidade_comercial')
    approval_vote(scope, karen, record, step_code: 'gratuidade_financeira')
    attrs = scope[:company].custom_attributes.deep_dup
    attrs[JrcCrm::CorporateProfile::KEY]['authorization_reference'] = 'New synthetic authority evidence'
    scope[:company].update!(custom_attributes: attrs)
    result = gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)
    expect(result[:status]).to eq('APPROVAL_REQUIRED')
    expect(result[:requests]).to include(include(id: record.id, state: 'stale'))
  end

  it 'does not enable the module or pass a corporate gift when enforcement has not been configured' do
    scope[:account].disable_features!('jrc_approvals')
    expect { JrcApprovals::CommercialGate.check!(resource: proposal, user: author.user, key: 'crm.proposal_send') }
      .to raise_error(JrcApprovals::Error, 'GRATUITY_POLICY_REQUIRED')
    expect(scope[:account].reload.feature_enabled?('jrc_approvals')).to be(false)
    expect(JrcApprovals::Policy.where(account: scope[:account]).count).to eq(0)
  end

  it 'requires a real boolean and supports membership conditions for typed gratuity lists' do
    fields = JrcApprovals::GratuityCatalog::FIELDS
    conditions = JrcApprovals::Conditions.new(fields)
    expect { conditions.validate!('field' => 'has_commercial_gratuity', 'op' => 'eq', 'value' => 'true') }
      .to raise_error(JrcApprovals::Error, 'INVALID_TYPED_VALUE')
    expect(conditions.match?({ 'field' => 'gratuity_type', 'op' => 'contains', 'value' => 'installation' },
                             'gratuity_type' => ['installation'])).to be(true)
  end

  it 'keeps the internal gratuity reason out of the public proposal representation' do
    item.update!(commercial_gratuity: { type: 'installation', reason: 'Synthetic internal justification' })
    internal = JrcCrm::ProposalSerializer.new(proposal).as_json[:items].first
    public_item = JrcCrm::ProposalSerializer.new(proposal, include_gratuity_intent: false).as_json[:items].first
    expect(internal[:commercial_gratuity]).to include('type' => 'installation')
    expect(public_item).not_to have_key(:commercial_gratuity)
    expect(public_item[:unit_price_cents]).to eq(100_000)
  end

  it 'refuses a complete sequence when official authorities have not been registered' do
    scope[:company].update!(custom_attributes: {})
    draft = manager.create!(code: 'missing-authorities', name: 'Synthetic unconfigured authorities',
                            module_key: 'crm', event_key: 'gratuity_request', issuer_company_id: scope[:company].id,
                            business_unit_id: scope[:unit].id, definition: definition)
    expect { manager.validate!(policy_id: draft.id, expected_version: draft.lock_version) }
      .to raise_error(JrcApprovals::Error, 'GRATUITY_AUTHORITIES_PENDING')
    expect(draft.reload).to have_attributes(state: 'draft', enabled: false, current_version_id: nil)
    expect { manager.publish!(policy_id: draft.id, expected_version: draft.lock_version) }
      .to raise_error(JrcApprovals::Error, 'POLICY_NOT_VALIDATED')
  end

  it 'does not replace missing policies with automatic approval in enforcement' do
    settings = scope[:account].custom_attributes.deep_dup
    settings[JrcApprovals::CommercialGate::SETTINGS_KEY] = { 'crm.proposal_send' => 'enforcement' }
    scope[:account].update!(custom_attributes: settings)
    expect { JrcApprovals::CommercialGate.check!(resource: proposal, user: author.user, key: 'crm.proposal_send') }
      .to raise_error(JrcApprovals::Error, 'POLICY_REQUIRED')
    expect(JrcApprovals::Policy.where(account: scope[:account])).to be_empty
    expect(JrcApprovals::Request.where(account: scope[:account])).to be_empty
    expect(proposal.reload).to be_draft
  end
end
