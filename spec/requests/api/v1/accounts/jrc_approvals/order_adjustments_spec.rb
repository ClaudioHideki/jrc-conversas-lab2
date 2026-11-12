require 'rails_helper'

RSpec.describe 'Bounded native order discount adjustment', :approval_core, :commercial_approvals, type: :request do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm']) }
  let(:reviewer) { approval_actor(scope, permissions: %w[jrc_approvals_decide jrc_approvals_adjust jrc_crm], role: :administrator) }
  let(:fixture) { commercial_fixture(scope, author) }
  let(:order) do
    source = scope[:account].jrc_crm_sales_orders.create!(owner: author.user, contact: fixture[:proposal].customer_contact,
      business_unit: scope[:unit], source_type: 'manual', order_origin: 'direct_sale', status: 'draft', discount_cents: 300)
    fixture[:proposal].proposal_items.order(:id).each do |item|
      native = JrcCrm::OrderFinancials.new(attributes: source.attributes, items: []).normalize_item(item.attributes)
      source.order_items.create!(native)
    end
    source.reload
  end
  let(:policy) do
    order
    service = JrcApprovals::Policies.new(account: scope[:account], user: author.user)
    rule = service.create!(code: 'synthetic-order-adjust', name: 'Synthetic order adjustment', module_key: 'crm', event_key: 'order_price',
      issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, definition: approval_definition([reviewer]))
    service.validate!(policy_id: rule.id, expected_version: rule.lock_version)
    service.publish!(policy_id: rule.id, expected_version: rule.reload.lock_version)
  end
  let(:record) do
    policy
    JrcApprovals::Requests.new(account: scope[:account], user: author.user)
      .create!(key: 'crm.order_price', resource_id: order.id, idempotency_key: 'synthetic-order-adjust').first
  end
  let(:service) { JrcApprovals::Adjustments.new(account: scope[:account], user: reviewer.user) }
  let(:input) do
    { request_id: record.id, changes: { 'discount_cents' => 100 }, mode: 'save', reason: 'Synthetic requested correction',
      expected_version: record.lock_version, idempotency_key: 'synthetic-discount-save' }
  end

  it 'saves a new review and retains the old snapshot without approving fulfillment' do
    old = record.attributes.slice('snapshot', 'stage_plan', 'requester_id')
    revised = service.call(**input)
    expect(order.reload.discount_cents).to eq(100)
    expect(order.status).to eq('draft')
    expect(revised.state).to eq('pending')
    expect(record.reload.attributes.slice(*old.keys)).to eq(old)
  end

  it 'applies and approves through the same native decision transaction' do
    revised = service.call(**input, mode: 'approve', step_code: 'review')
    expect(revised.state).to eq('approved')
    expect(order.reload.status).to eq('draft')
    expect(revised.decisions.count).to eq(1)
  end

  it 'replays an identical intent without a second revision or monetary change' do
    values = input
    first = service.call(**values)
    count = JrcApprovals::Request.count
    second = service.call(**values)
    expect(second.id).to eq(first.id)
    expect(JrcApprovals::Request.count).to eq(count)
  end

  it 'rolls back a value capped by the native calculator' do
    values = input.merge(changes: { 'discount_cents' => order.financial_summary.fetch(:products_cents) + 1 })
    before = [order.reload.attributes, record.reload.attributes, JrcApprovals::Request.count, JrcCrm::AuditEvent.count]
    expect { service.call(**values) }.to raise_error(JrcApprovals::Error, 'INVALID_COMMERCIAL_TERMS')
    expect([order.reload.attributes, record.reload.attributes, JrcApprovals::Request.count, JrcCrm::AuditEvent.count]).to eq(before)
  end

  it 'never accepts a request to change owner, customer, state or arbitrary fields' do
    expect { service.call(**input.merge(changes: { 'discount_cents' => 100, 'status' => 'approved' })) }
      .to raise_error(JrcApprovals::Error, 'INVALID_ADJUSTMENT_FIELDS')
    expect(order.reload.status).to eq('draft')
  end

  it 'does not expose adjustment fields to a reviewer lacking native CRM ownership or administration' do
    restricted = approval_actor(scope, permissions: %w[jrc_approvals_decide jrc_approvals_adjust jrc_crm], role: :agent)
    expect(JrcApprovals::Adjustments.new(account: scope[:account], user: restricted.user).options(record)).to be_nil
  end
end
