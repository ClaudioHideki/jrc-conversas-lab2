# Run: ruby test/jrc_consolidation/financial_domain_test.rb
# Executes production Ruby financial services. No database/framework substitute.
require 'minitest/autorun'
require 'json'
ROOT = File.expand_path('../..', __dir__) unless defined?(ROOT)
%w[commercial_financials order_financials commercial_item_allocation commission_protection].each do |name|
  require File.join(ROOT, "app/services/jrc_crm/#{name}")
end

class CommercialFinancialDomainTest < Minitest::Test
  F = JrcCrm::CommercialFinancials
  O = JrcCrm::OrderFinancials
  def row(**values)
    { product_id: 1, name: 'Servico JRC', quantity: 1, unit_cents: 100_000,
      snapshot: { billing_model: 'one_time' } }.merge(values)
  end
  def calc(attributes = {}, items = [row])
    F.new(attributes: { first_due_date: '2026-09-29', payment_condition: 'cash' }.merge(attributes), items: items).call
  end
  def test_cash_conserves_total
    f = calc
    assert_equal 100_000, f[:total_cents]
    assert_equal 100_000, f[:cash_payment_cents]
    assert_equal [], f[:installment_plan_cents]
    assert_equal f[:total_cents], f[:payments].sum { |p| p[:value] }
  end
  def test_entry_and_financed_freight
    f = calc(payment_condition: 'down_payment_installments', down_payment_cents: 30_000,
      installments_count: 3, shipping_mode: 'separate', shipping_cents: 5001, shipping_in_installments: true)
    assert_equal 105_001, f[:total_cents]
    assert_equal 75_001, f[:balance_cents]
    assert_equal [25_001, 25_000, 25_000], f[:installment_plan_cents]
    assert_equal f[:total_cents], f[:payments].sum { |p| p[:value] }
  end
  def test_entry_and_upfront_freight_not_double_charged
    f = calc(payment_condition: 'down_payment_installments', down_payment_cents: 30_000,
      installments_count: 3, shipping_mode: 'separate', shipping_cents: 5000, shipping_in_installments: false)
    assert_equal 100_000, f[:payable_base_cents]
    assert_equal 70_000, f[:balance_cents]
    assert_equal [23_334, 23_333, 23_333], f[:installment_plan_cents]
    assert_equal 5000, f[:upfront_shipping_cents]
    assert_equal 105_000, f[:payments].sum { |p| p[:value] }
  end
  def test_included_and_non_applicable_freight_charge_zero
    %w[included not_applicable].each do |mode|
      f = calc(shipping_mode: mode, shipping_cents: 12_000)
      assert_equal 0, f[:shipping_cents]
      assert_equal 100_000, f[:total_cents]
    end
  end
  def test_cash_does_not_preserve_stale_down_payment
    f = calc(down_payment_cents: 1234, installments_count: 12)
    assert_equal 0, f[:down_payment_cents]
    assert_equal 1, f[:installments_count]
    assert_equal 100_000, f[:payments].sum { |p| p[:value] }
  end
  def test_invalid_entry_over_financeable_amount
    assert_raises(F::InvalidTerms) { calc(payment_condition: 'down_payment_installments', down_payment_cents: 100_001) }
    assert_raises(F::InvalidTerms) do
      calc(payment_condition: 'down_payment_installments', down_payment_cents: 100_001,
        shipping_mode: 'separate', shipping_cents: 5000, shipping_in_installments: false)
    end
  end
  def test_full_entry_has_zero_balance
    f = calc(payment_condition: 'down_payment_installments', down_payment_cents: 100_000, installments_count: 3)
    assert_equal [0, 0, 0], f[:installment_plan_cents]
    assert_equal 100_000, f[:payments].sum { |p| p[:value] }
  end
  def test_line_general_discounts_and_tax
    f = calc({ discount_cents: 1000, shipping_mode: 'separate', shipping_cents: 200,
      snapshot: { taxes_percent: 10 } }, [row(quantity: 2, unit_cents: 10_000, discount_cents: 2000)])
    assert_equal 20_000, f[:subtotal_cents]
    assert_equal 18_000, f[:products_cents]
    assert_equal 3000, f[:total_discount_cents]
    assert_equal 1720, f[:taxes_cents]
    assert_equal 18_920, f[:total_cents]
  end
  def test_monthly_initial_period_is_not_lost_or_double_counted
    f = calc({}, [row(unit_cents: 1200, snapshot: { billing_model: 'monthly', setup_fee_cents: 3000 })])
    assert_equal 4200, f[:total_cents]
    assert_equal 1200, f[:monthly_cents]
    assert_equal 4200, f[:items].first[:one_time_cents]
  end
  def test_optional_monthly_fee_suppresses_future_recurrence_not_accepted_initial_price
    f = calc({ has_monthly_fee: false }, [row(unit_cents: 1200, snapshot: { billing_model: 'monthly', setup_fee_cents: 3000 })])
    assert_equal 4200, f[:total_cents]
    assert_equal 0, f[:monthly_cents]
    assert_equal 0, f[:items].first[:recurring_cents]
  end
  def test_explicit_manual_recurrence_survives_persistence
    terms = calc({}, [row(unit_cents: 4_000_000, recurring_cents: 200_000)])
    assert_equal 4_000_000, terms[:total_cents]
    assert_equal 200_000, terms[:monthly_cents]
    rebuilt = O.new(attributes: O.attributes_for(terms).merge(snapshot: O.snapshot_for(terms)), items: terms[:items]).call
    assert O.same_terms?(terms, rebuilt)
    disabled = O.new(attributes: O.attributes_for(terms).merge(snapshot: O.snapshot_for(terms), has_monthly_fee: false), items: terms[:items]).call
    assert_equal 0, disabled[:monthly_cents]
    assert_equal 4_000_000, disabled[:total_cents]
  end
  def test_annual_monthly_equivalent
    f = calc({}, [row(unit_cents: 120_001, snapshot: { billing_model: 'annual' })])
    assert_equal 120_001, f[:total_cents]
    assert_equal 10_000, f[:monthly_cents]
  end
  def test_partial_quantity_and_half_up_rounding
    f = calc({}, [row(unit_cents: 999, quantity: '0.125')])
    assert_equal 125, f[:products_cents]
    assert_raises(F::InvalidTerms) { calc({}, [row(quantity: '0.1234')]) }
  end
  def test_invalid_values_and_limits
    [-1, 'NaN', 'Infinity', 'not-money'].each { |v| assert_raises(F::InvalidTerms) { calc(shipping_cents: v) } }
    [0, -1, 121, '2.5', 2.5].each { |v| assert_raises(F::InvalidTerms) { calc(payment_condition: 'installments', installments_count: v) } }
    [0, -1, 'NaN'].each { |v| assert_raises(F::InvalidTerms) { calc({}, [row(quantity: v)]) } }
    assert_raises(F::InvalidTerms) { calc(payment_condition: 'invented') }
    assert_raises(F::InvalidTerms) { calc(shipping_mode: 'invented') }
    assert_raises(F::InvalidTerms) { calc(first_due_date: '2026-02-30') }
  end
  def test_end_of_month_schedule
    f = calc(payment_condition: 'installments', installments_count: 3, first_due_date: '2027-01-31')
    assert_equal %w[2027-01-31 2027-02-28 2027-03-31], f[:installments].map { |p| p[:date] }
  end
  def test_proposal_order_contract_roundtrip_all_combinations
    %w[cash installments down_payment_installments].product(%w[included separate not_applicable], [true, false], [true, false]).each do |condition, shipping_mode, financed, monthly|
      initial = calc({ payment_condition: condition, shipping_mode: shipping_mode, shipping_cents: 1234,
        shipping_in_installments: financed, has_monthly_fee: monthly, installments_count: 7,
        down_payment_cents: 2345, discount_cents: 123 },
        [row(quantity: 2, unit_cents: 9876, discount_cents: 321),
         row(product_id: 2, unit_cents: 1200, snapshot: { billing_model: 'monthly', setup_fee_cents: 500 })])
      snapshot = JSON.parse(JSON.generate(O.snapshot_for(initial)))
      attrs = O.attributes_for(initial).merge(snapshot: snapshot)
      stored_items = JSON.parse(JSON.generate(initial[:items]))
      order = O.new(attributes: attrs, items: stored_items).call
      assert O.same_terms?(initial, order), [condition, shipping_mode, financed, monthly].inspect
      assert_equal initial.except(:items), order.except(:items)
      # Contract persists exactly this immutable financial snapshot.
      contract = JSON.parse(JSON.generate(O.snapshot_for(order)['financials']))
      assert_equal initial[:total_cents], contract['total_cents']
      assert_equal initial[:monthly_cents], contract['monthly_cents']
      assert_equal initial[:installment_plan_cents], contract['installment_plan_cents']
    end
  end
  def test_tax_and_percentage_discount_roundtrip
    initial = calc({ payment_condition: 'down_payment_installments', down_payment_cents: 1234, installments_count: 7,
      shipping_mode: 'separate', shipping_cents: 5000, snapshot: { discount_percent: 7.33, taxes_percent: 12.34 } })
    restored = O.new(attributes: O.attributes_for(initial).merge(snapshot: O.snapshot_for(initial)), items: initial[:items]).call
    assert O.same_terms?(initial, restored)
    assert_equal initial[:taxes_cents], restored[:taxes_cents]
    assert_equal initial[:discount_cents], restored[:discount_cents]
  end
  def test_fuzz_conservation_and_persistence
    random = Random.new(20260929)
    1500.times do
      items = Array.new(random.rand(1..8)) do |i|
        row(product_id: i + 1, quantity: random.rand(1..10), unit_cents: random.rand(1..100_000),
            discount_percent: random.rand(0..60), snapshot: { billing_model: %w[one_time monthly annual][random.rand(3)], setup_fee_cents: random.rand(0..1000) })
      end
      terms = calc({ payment_condition: 'down_payment_installments', installments_count: random.rand(1..120),
        snapshot: { taxes_percent: random.rand(0..30) }, down_payment_cents: 0, shipping_mode: 'separate', shipping_cents: random.rand(0..10000),
        shipping_in_installments: random.rand(2).zero?, has_monthly_fee: random.rand(2).zero?, discount_cents: random.rand(0..5000) }, items)
      assert_equal terms[:total_cents], terms[:payments].sum { |row| row[:value] }
      assert_equal terms[:balance_cents], terms[:installment_plan_cents].sum
      assert_operator terms[:installment_plan_cents].max - terms[:installment_plan_cents].min, :<=, 1
      rebuilt = O.new(attributes: O.attributes_for(terms).merge(snapshot: O.snapshot_for(terms)), items: terms[:items]).call
      assert O.same_terms?(terms, rebuilt)
    end
  end
  def test_product_allocation_uses_only_item_values
    values = JrcCrm::CommercialItemAllocation.call(items: [
      { product_id: 1, quantity: 2, one_time_cents: 30_000, recurring_cents: 1000 },
      { product_id: 2, quantity: 1, one_time_cents: 70_000, recurring_cents: 2000 }
    ], discount_cents: 10_000)
    assert_equal [27_000, 63_000], values.map { |v| v[:revenue_cents] }
    assert_equal 90_000, values.sum { |v| v[:revenue_cents] }
    assert_equal 27_000, values.select { |v| v[:product_id] == 1 }.sum { |v| v[:revenue_cents] }
  end
  def test_product_allocation_exact_rounding_and_no_monthly
    values = JrcCrm::CommercialItemAllocation.call(items: [
      { product_id: 1, quantity: 1, one_time_cents: 1, recurring_cents: 9 },
      { product_id: 2, quantity: 1, one_time_cents: 1, recurring_cents: 9 },
      { product_id: 3, quantity: 1, one_time_cents: 1, recurring_cents: 9 }
    ], discount_cents: 1, monthly_enabled: false)
    assert_equal 2, values.sum { |v| v[:revenue_cents] }
    assert_equal 0, values.sum { |v| v[:monthly_cents] }
  end
  def test_final_commission_fields_and_unknown_margin
    protection = JrcCrm::CommissionProtection
    assert protection.final?('paid')
    assert protection.final?('reversed')
    refute protection.final?('released')
    assert_equal %w[base_cents rate_percent commission_cents], protection.changed_fields('base_cents' => [1, 2], 'rate_percent' => [1, 2], 'commission_cents' => [1, 2], 'notes' => ['', 'x'])
    assert_nil protection.margin('total_cents' => 500_000)
    assert_nil protection.margin('margin_cents' => '')
    assert_nil protection.margin('margin_cents' => 'NaN')
    assert_equal 0, protection.margin('margin_cents' => 0)
    assert_equal(-123, protection.margin('margin_cents' => -123))
  end
end
