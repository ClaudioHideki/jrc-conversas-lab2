# Standalone tests of real production calculation and synchronization guards.
# The two guard tests use relation/record doubles, NOT a database or Rails boot.
require 'minitest/autorun'
require 'ostruct'
ROOT = File.expand_path('../..', __dir__) unless defined?(ROOT)
%w[commercial_financials commission_protection commission_rules_engine order_workflow_sync_service].each do |name|
  require File.join(ROOT, "app/services/jrc_crm/#{name}")
end
class CommissionDomainTest < Minitest::Test
  def calculate(rules = {}, sale = {}, **extra)
    JrcCrm::CommissionRulesEngine.new(rules: { rate_percent: 10 }.merge(rules), sale: { total_cents: 100_000 }.merge(sale), **extra).call
  end
  def test_flat_rate
    assert_equal 10_000, calculate[:commission_cents]
  end
  def test_integer_half_up
    assert_equal 1, calculate({ rate_percent: 50 }, { total_cents: 1 })[:commission_cents]
  end
  def test_share
    assert_equal 3500, calculate({}, {}, share_percent: 35)[:commission_cents]
  end
  def test_monthly_base_not_order_total
    assert_equal 1000, calculate({ base: 'monthly_cents' }, { monthly_cents: 10_000 })[:commission_cents]
  end
  def test_received_base
    assert_equal 2500, calculate({ base: 'received_cents' }, { received_cents: 25_000 })[:commission_cents]
  end
  def test_missing_margin_fails_closed
    [nil, '', 'NaN', 'Infinity'].each do |margin|
      assert_raises(ArgumentError) { calculate({ base: 'margin_cents' }, { margin_cents: margin }) }
    end
  end
  def test_zero_margin_is_not_fallback
    assert_equal 0, calculate({ base: 'margin_cents' }, { margin_cents: 0 })[:commission_cents]
  end
  def test_negative_margin_never_creates_commission
    assert_equal 0, calculate({ base: 'margin_cents' }, { margin_cents: -900 })[:commission_cents]
  end
  def test_actual_margin
    result = calculate({ base: 'margin_cents' }, { margin_cents: 20_000 })
    assert_equal 20_000, result[:base_cents]
    assert_equal 2000, result[:commission_cents]
    assert_equal 'margin_cents', result.dig(:calculation, :base_kind)
  end
  def test_value_tiers
    result = calculate({ tiers: [{ min_cents: 0, max_cents: 99_999, rate_percent: 5 }, { min_cents: 100_000, rate_percent: 12 }] })
    assert_equal 12_000, result[:commission_cents]
    assert_equal 100_000, result.dig(:selected_tier, :min_cents)
  end
  def test_attainment_tier_and_bonuses
    result = calculate({ tier_basis: 'goal_attainment', tiers: [{ min_percent: 100, rate_percent: 15 }],
      bonuses: [{ attainment_percent: 100, amount_cents: 1000 }, { attainment_percent: 110, percent: 10 }] }, {}, attainment_percent: 120)
    assert_equal 17_500, result[:commission_cents]
    assert_equal 2500, result[:bonus_cents]
  end
  def test_no_attainment_no_bonus
    assert_equal 10_000, calculate({ bonuses: [{ attainment_percent: 0, amount_cents: 1000 }] })[:commission_cents]
  end
  def test_invalid_share_and_rate
    [-1, 101, 'NaN'].each { |v| assert_raises(ArgumentError) { calculate({}, {}, share_percent: v) } }
    assert_raises(ArgumentError) { calculate(rate_percent: -1) }
  end
  def test_string_keys
    result = JrcCrm::CommissionRulesEngine.new(rules: { 'rate_percent' => '7.5' }, sale: { 'total_cents' => 1000 }).call
    assert_equal 75, result[:commission_cents]
  end
  %w[paid reversed].each do |status|
    define_method("test_sync_skips_#{status}_before_selecting_program_or_assigning_values") do
      commission = Object.new
      commission.define_singleton_method(:persisted?) { true }
      commission.define_singleton_method(:status) { status }
      commission.define_singleton_method(:assign_attributes) { |*| raise 'MUST NOT MODIFY FINAL COMMISSION' }
      relation = Object.new
      locked = false
      relation.define_singleton_method(:lock) { locked = true; self }
      relation.define_singleton_method(:find_or_initialize_by) { |**| commission }
      order = OpenStruct.new(commissions: relation, owner: Object.new)
      service = JrcCrm::OrderWorkflowSyncService.new(order: order, actor: nil)
      service.define_singleton_method(:eligible_program) { raise 'MUST NOT EVEN RESELECT PROGRAM' }
      assert_nil service.send(:sync_commission!)
      assert locked
      assert_equal status, commission.status
    end
  end
end
