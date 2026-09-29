require 'rails_helper'

RSpec.describe 'Consolidated persisted finance guards' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:other_user) { create(:user, account: account) }
  let(:unit) { JrcCrm::BusinessUnit.create!(account: account, name: 'Unidade JRC', code: 'JRC-01') }
  let(:team) { create(:team, account: account) }
  let(:product) { create(:jrc_crm_product, account: account) }
  let(:order) do
    JrcCrm::SalesOrder.create!(account: account, owner: user, business_unit: unit, status: 'approved', source_type: 'manual',
      products_cents: 100_000, total_cents: 90_000, discount_cents: 10_000, sold_at: Time.current,
      snapshot: { margin_cents: 20_000 })
  end
  let(:commission) do
    JrcCrm::SalesCommission.create!(account: account, sales_order: order, user: user,
      status: 'paid', base_cents: 100_000, rate_percent: 10, paid_at: Time.current)
  end

  it 'rejects a paid commission value mutation at model level' do
    expect(commission.update(base_cents: 200_000, rate_percent: 20)).to be(false)
    expect(commission.reload.base_cents).to eq(100_000)
    expect(commission.commission_cents).to eq(10_000)
  end

  it 'does not recalculate a paid commission in order synchronization' do
    before = commission.attributes.slice(*JrcCrm::CommissionProtection::FINANCIAL_FIELDS)
    JrcCrm::OrderWorkflowSyncService.new(order: order, actor: user).send(:sync_commission!)
    expect(commission.reload.attributes.slice(*JrcCrm::CommissionProtection::FINANCIAL_FIELDS)).to eq(before)
  end

  it 'permits explicit reversal without changing paid values and prevents reopening' do
    expect(commission.update(status: 'reversed', notes: 'Ajuste explicito autorizado')).to be(true)
    expect(commission.commission_cents).to eq(10_000)
    expect(commission.update(status: 'released')).to be(false)
  end

  it 'does not substitute the order total for an unknown margin' do
    order.update!(snapshot: {})
    JrcCrm::CommissionProgram.create!(account: account, name: 'Margem', active: true,
      release_condition: 'order_approved', rules: { base: 'margin_cents', rate_percent: 10 })
    expect { JrcCrm::OrderWorkflowSyncService.new(order: order, actor: user).send(:sync_commission!) }
      .not_to change(JrcCrm::SalesCommission, :count)
    expect(JrcCrm::AuditEvent.where(event_type: 'commission_calculation_pending', resource_id: order.id)).to exist
  end

  it 'intersects user team unit and product and counts only eligible net items' do
    create(:team_member, team: team, user: user)
    order.order_items.create!(product: product, name: 'Eligible', quantity: 1, unit_cents: 30_000, one_time_cents: 30_000)
    order.order_items.create!(name: 'Other', quantity: 1, unit_cents: 70_000, one_time_cents: 70_000)
    JrcCrm::SalesOrder.create!(account: account, owner: other_user, business_unit: unit, status: 'approved',
      source_type: 'manual', total_cents: 999_999, sold_at: Time.current)
    goal = JrcCrm::SalesGoal.create!(account: account, name: 'Scoped', user: user, team: team, business_unit: unit,
      product: product, scope_kind: 'product', status: 'active', metric: 'revenue',
      calculation_method: 'approved_orders', period_start: Date.current.beginning_of_month,
      period_end: Date.current.end_of_month, target_cents: 30_000)
    expect(JrcCrm::GoalProgressService.new(goal: goal).call[:realized]).to eq(27_000)
    expect(JrcCrm::GoalProgressService.new(goal: goal, user_id: other_user.id).call[:realized]).to eq(0)
  end

  it 'rejects a team belonging to another account in a goal' do
    foreign_team = create(:team)
    goal = JrcCrm::SalesGoal.new(account: account, team: foreign_team, scope_kind: 'team', status: 'active',
      period_start: Date.current, period_end: Date.current + 30, target_cents: 1000)
    expect(goal).not_to be_valid
    expect(goal.errors[:team]).not_to be_empty
  end

  it 'locks a manual order as soon as a contractual snapshot exists, including draft' do
    JrcCrm::Contract.create!(account: account, sales_order: order, owner: user, status: 'draft')
    expect(order.commercial_terms_locked?).to be(true)
  end
end
