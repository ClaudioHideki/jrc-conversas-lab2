require 'rails_helper'

RSpec.describe 'Native commercial approval integration', type: :model, approval_core: true, commercial_approvals: true do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm'], role: :administrator) }
  let(:approver) { approval_actor(scope, permissions: ['jrc_approvals_decide', 'jrc_crm']) }
  let(:fixture) { commercial_fixture(scope, author) }
  let(:proposal) { fixture[:proposal] }
  let(:gate) { JrcApprovals::CommercialGate.new(account: scope[:account], user: author.user) }

  it 'keeps feature disabled as the native default, with no policy or domain effect' do
    proposal
    scope[:account].disable_features!('jrc_approvals')
    expect(JrcApprovals::CommercialGate.check!(resource: proposal, user: author.user, key: 'crm.proposal_send'))
      .to eq(mode: 'disabled', status: 'legacy', required: false)
    expect(scope[:account].reload.feature_enabled?('jrc_approvals')).to be(false)
    expect(JrcApprovals::Policy.where(account: scope[:account]).count).to eq(0)
  end

  [1100, 900].each do |net|
    it "does not open a price exception for net #{net} at/above the floor" do
      fixture = commercial_fixture(scope, author, discount: 0)
      fixture[:proposal].proposal_items.first.update!(unit_price_cents: net)
      expect(commercial_request(scope, author, fixture[:proposal])).to eq([])
      expect(JrcApprovals::Request.where(account: scope[:account]).count).to eq(0)
    end
  end

  it 'creates a below-floor request from native references and requires a designated vote' do
    commercial_policy(scope, author, [approver])
    record = commercial_request(scope, author, proposal).first
    expect(record.state).to eq('pending')
    expect(record.snapshot['values']).to include('price_status' => 'evaluated', 'below_minimum_count' => 1)
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)[:status]).to eq('APPROVAL_REQUIRED')
    approval_vote(scope, approver, record)
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)[:status]).to eq('ready')
    expect(proposal.reload.status).to eq('draft')
    expect(proposal.sales_orders.count).to eq(0)
  end

  it 'never silently approves a zero or missing minimum in enforcement' do
    fixture[:product].update!(minimum_price_cents: 0)
    commercial_mode(scope[:account], 'crm.proposal_send', 'enforcement')
    expect { proposal.with_lock { JrcApprovals::CommercialGate.check!(resource: proposal, user: author.user, key: 'crm.proposal_send') } }
      .to raise_error(JrcApprovals::Error, 'PRICE_CONTEXT_PENDING')
    expect { commercial_request(scope, author, proposal) }.to raise_error(JrcApprovals::Error, 'PRICE_CONTEXT_PENDING')
    expect(JrcApprovals::Request.where(account: scope[:account]).count).to eq(0)
  end

  it 'observes missing policy in shadow without blocking or granting authorization' do
    expect(JrcApprovals::CommercialGate.check!(resource: proposal, user: author.user, key: 'crm.proposal_send'))
      .to include(mode: 'shadow', status: 'POLICY_REQUIRED')
    expect(JrcApprovals::Request.where(account: scope[:account]).count).to eq(0)
  end

  %i[unit_price_cents quantity discount_cents].each do |field|
    it "invalidates an approved request after relevant #{field} editing without erasing history" do
      commercial_policy(scope, author, [approver])
      record = commercial_request(scope, author, proposal).first
      approval_vote(scope, approver, record)
      item = proposal.proposal_items.first
      value = { unit_price_cents: 1200, quantity: 2, discount_cents: 250 }.fetch(field)
      proposal.with_lock do
        item.update!(field => value)
        JrcApprovals::CommercialInvalidation.call(resource: proposal.reload, user: author.user)
      end
      expect(record.reload.state).to eq('stale')
      expect(record.decisions.count).to eq(1)
      expect(JrcApprovals::AuditEvent.where(request_id: record.id, event_type: 'request_invalidate').count).to eq(1)
    end
  end

  it 'rejects a changed price reference and currency even if the old request remains approved' do
    commercial_policy(scope, author, [approver])
    record = commercial_request(scope, author, proposal).first
    approval_vote(scope, approver, record)
    fixture[:product].update!(minimum_price_cents: 950)
    result = gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)
    expect(result[:status]).to eq('APPROVAL_REQUIRED')
    expect(result[:requests]).to include(include(id: record.id, state: 'stale'))
    fixture[:product].update!(currency: 'USD')
    expect(record.reload.snapshot).not_to eq(JrcApprovals::Catalog.snapshot(account: scope[:account], user: author.user,
      key: 'crm.proposal_send', resource_id: proposal.id))
  end

  it 'requires every accumulated policy approval and never substitutes operational or technical approval' do
    2.times { commercial_policy(scope, author, [approver], selection: 'accumulate') }
    records = commercial_request(scope, author, proposal)
    expect(records.length).to eq(2)
    approval_vote(scope, approver, records.first)
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)[:status]).to eq('APPROVAL_REQUIRED')
    approval_vote(scope, approver, records.last)
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)[:status]).to eq('ready')
    proposal.update!(technical_approval_status: 'pending')
    expect { JrcCrm::ProposalDeliveryService.new(proposal: proposal, actor: author.user).call }
      .to raise_error(ArgumentError, 'Conclua as aprovações internas antes do envio.')
    expect(proposal.sales_orders.count).to eq(0)
  end

  it 'rejects cross-tenant access before price capture' do
    other = approval_scope
    outsider = approval_actor(other, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm'])
    proposal
    expect(JrcApprovals::NativePriceContext).not_to receive(:new)
    expect { JrcApprovals::CommercialGate.new(account: other[:account], user: outsider.user)
      .request!(key: 'crm.proposal_send', resource_id: proposal.id, idempotency_key: 'cross') }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'refuses a generic admin and Backoffice operator as managerial voters' do
    commercial_policy(scope, author, [approver])
    record = commercial_request(scope, author, proposal).first
    admin = create(:user, account: scope[:account], role: :administrator)
    membership = scope[:account].account_users.find_by!(user: admin)
    expect { approval_vote(scope, membership, record) }.to raise_error(Pundit::NotAuthorizedError)
    operator = approval_actor(scope, permissions: ['jrc_crm', 'jrc_approvals_request_create'])
    expect { approval_vote(scope, operator, record) }.to raise_error(Pundit::NotAuthorizedError)
    expect(record.reload.decisions.count).to eq(0)
  end

  it 'does not let one proposal authorize another in the same company and unit' do
    commercial_policy(scope, author, [approver])
    record = commercial_request(scope, author, proposal).first
    approval_vote(scope, approver, record)
    another = commercial_fixture(scope, author)[:proposal]
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: another.id)[:status]).to eq('APPROVAL_REQUIRED')
  end

  it 'preserves key/content idempotency and refuses changed quantities with the same key' do
    commercial_policy(scope, author, [approver])
    one = commercial_request(scope, author, proposal, idempotency_key: 'one').first
    expect(commercial_request(scope, author, proposal, idempotency_key: 'one').first.id).to eq(one.id)
    proposal.proposal_items.first.update!(quantity: 2)
    expect { commercial_request(scope, author, proposal, idempotency_key: 'one') }
      .to raise_error(JrcApprovals::Error, 'IDEMPOTENCY_CONTENT_CONFLICT')
  end

  it 'simulates authorized resources and synthetic typed context without any side effect' do
    commercial_policy(scope, author, [approver])
    before = [JrcApprovals::Request.count, JrcApprovals::Decision.count, JrcApprovals::AuditEvent.count,
              JrcCrm::SalesOrder.count, JrcCrm::Contract.count, Message.count, proposal.reload.attributes]
    result = JrcApprovals::Simulation.new(account: scope[:account], user: author.user)
      .call(key: 'crm.proposal_send', resource_id: proposal.id)
    expect(result[:versions].first[:plan].first['principal_ids']).to eq([approver.id])
    expect(result[:effects]).to eq([])
    expect([JrcApprovals::Request.count, JrcApprovals::Decision.count, JrcApprovals::AuditEvent.count,
      JrcCrm::SalesOrder.count, JrcCrm::Contract.count, Message.count, proposal.reload.attributes]).to eq(before)
    context = JrcApprovals::Catalog.snapshot(account: scope[:account], user: author.user, key: 'crm.proposal_send', resource_id: proposal.id)
      .slice('issuer_company_id', 'business_unit_id', 'values')
    expect(JrcApprovals::Simulation.new(account: scope[:account], user: author.user)
      .call(key: 'crm.proposal_send', context: context)[:effects]).to eq([])
  end

  it 'reuses one published price policy version across proposal and direct order while binding separate resources' do
    family = commercial_policy(scope, author, [approver], key: 'crm.price_exception')
    proposal_request = commercial_request(scope, author, proposal).first
    approval_vote(scope, approver, proposal_request)
    order = JrcCrm::SalesOrder.create!(account: scope[:account], owner: author.user, created_by: author.user,
      contact: fixture[:contact], business_unit: scope[:unit], source_type: 'manual', status: 'draft')
    terms = proposal.financial_summary
    order.update!(JrcCrm::OrderFinancials.attributes_for(terms).merge(snapshot: JrcCrm::OrderFinancials.snapshot_for(terms)))
    terms[:items].each { |item| order.order_items.create!(item) }
    result = gate.evaluate(key: 'crm.order_price', resource_id: order.id)
    expect(result[:policy_version_ids]).to eq([family.current_version_id])
    expect(result[:status]).to eq('APPROVAL_REQUIRED')
    order_request = commercial_request(scope, author, order, key: 'crm.order_price').first
    expect(order_request.policy_version_id).to eq(proposal_request.policy_version_id)
    expect(order_request.resource_type).to eq('JrcCrm::SalesOrder')
    expect(order_request.snapshot).not_to eq(proposal_request.snapshot)
    expect { JrcApprovals::Requests.new(account: scope[:account], user: author.user)
      .create!(key: 'crm.price_exception', resource_id: proposal.id, idempotency_key: 'template') }
      .to raise_error(JrcApprovals::Error, 'POLICY_TEMPLATE_ONLY')
  end

  it 'rejects conflicting family and action-specific policies before publication' do
    commercial_policy(scope, author, [approver], key: 'crm.price_exception')
    expect { commercial_policy(scope, author, [approver], key: 'crm.proposal_send') }
      .to raise_error(JrcApprovals::Error, 'POLICY_SELECTION_CONFLICT')
  end

  it 'evaluates native deal items through E1 without changing the deal valuation or data' do
    proposal
    pipeline = JrcCrm::DefaultPipelineService.new(scope[:account]).perform
    deal = JrcCrm::Deal.create!(account: scope[:account], owner: author.user, contact: fixture[:contact],
      metadata: { business_unit_id: scope[:unit].id }, pipeline: pipeline, stage: pipeline.stages.active.order(:position).first,
      title: 'Synthetic deal', value_cents: 123456, currency: 'BRL')
    deal.deal_products.create!(product: fixture[:product], quantity: 1, unit_price_cents: 1000, discount_cents: 200)
    before = deal.reload.attributes.deep_dup
    commercial_policy(scope, author, [approver], key: 'crm.price_exception')
    record = commercial_request(scope, author, deal, key: 'crm.deal_price').first
    expect(record.snapshot['values']).to include('below_minimum_count' => 1, 'total_cents' => 800, 'currency' => 'BRL')
    expect(deal.reload.attributes).to eq(before)
    expect(deal.value_cents).to eq(123456)
  end

  it 'keeps native unit/billing incompatibilities pending rather than inventing conversions' do
    item = proposal.proposal_items.first
    item.update!(unit_name: 'another-unit')
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)[:status]).to eq('PRICE_CONTEXT_PENDING')
    item.update!(unit_name: 'unidade', billing_model: 'annual')
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)[:status]).to eq('PRICE_CONTEXT_PENDING')
  end

  it 'does not reuse an older approval after a new pending or rejected request' do
    commercial_policy(scope, author, [approver])
    previous = commercial_request(scope, author, proposal).first
    approval_vote(scope, approver, previous)
    current = commercial_request(scope, author, proposal).first
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)[:status]).to eq('APPROVAL_REQUIRED')
    approval_vote(scope, approver, current, decision: 'rejected')
    expect(previous.reload.state).to eq('approved')
    expect(current.reload.state).to eq('rejected')
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)[:status]).to eq('APPROVAL_REQUIRED')
  end

  it 'requires recorded quorum evidence rather than accepting a state-only approved request' do
    commercial_policy(scope, author, [approver])
    record = commercial_request(scope, author, proposal).first
    record.update!(state: 'approved')
    expect(record.decisions.count).to eq(0)
    expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)[:status]).to eq('APPROVAL_REQUIRED')
  end

  it 'keeps fingerprints invariant across API and CRM reporting time zones' do
    commercial_policy(scope, author, [approver])
    record = commercial_request(scope, author, proposal).first
    approval_vote(scope, approver, record)
    Time.use_zone('America/Sao_Paulo') do
      expect(gate.evaluate(key: 'crm.proposal_send', resource_id: proposal.id)[:status]).to eq('ready')
    end
  end

  it 'invalidates approval after changing the persisted issuer identity without trusting it as organizational authorization' do
    commercial_policy(scope, author, [approver])
    record = commercial_request(scope, author, proposal).first
    approval_vote(scope, approver, record)
    proposal.with_lock do
      proposal.update!(issuer_company_name: 'Another synthetic issuer label')
      JrcApprovals::CommercialInvalidation.call(resource: proposal.reload, user: author.user)
    end
    expect(record.reload.state).to eq('stale')
    expect(record.issuer_company_id).to eq(scope[:company].id)
  end

  it 'rejects malformed activation configuration without granting an effect or choosing enforcement by omission' do
    proposal
    scope[:account].update!(custom_attributes: { 'jrc_approval_gates' => nil })
    expect { JrcApprovals::CommercialGate.check!(resource: proposal, user: author.user, key: 'crm.proposal_send') }
      .to raise_error(JrcApprovals::Error, 'INVALID_GATE_MODE')
    expect(Message.where(account: scope[:account]).count).to eq(0)
  end

  it 'refuses publication when a declared commercial approver cannot access the domain context' do
    proposal
    missing_domain = approval_actor(scope, permissions: ['jrc_approvals_decide'])
    expect { commercial_policy(scope, author, [missing_domain]) }.to raise_error(JrcApprovals::Error, 'INSUFFICIENT_APPROVERS')
    expect(JrcApprovals::Policy.where(account: scope[:account], enabled: true).count).to eq(0)
  end
end
