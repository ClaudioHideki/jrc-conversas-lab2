# Pure production-service tests; no Rails, database, policy or external side effect.
require 'minitest/autorun'
require 'json'
require_relative '../../app/services/jrc_crm/commercial_financials'
require_relative '../../app/services/jrc_crm/commercial_price_evaluation'
require_relative '../../app/services/jrc_crm/commercial_item_allocation'

class CommercialPriceEvaluationTest < Minitest::Test
  F = JrcCrm::CommercialFinancials

  def item(**values)
    { product_id: 1, quantity: 1, unit_price_cents: 1000, billing_model: 'monthly', unit_name: 'license',
      price_reference: { minimum_price_cents: 900, currency: 'BRL', billing_model: 'monthly', unit_name: 'license' } }.merge(values)
  end

  def evaluate(items = [item], attributes = {}, **options)
    F.new(attributes: { currency: 'BRL', first_due_date: '2026-10-12' }.merge(attributes), items: items).evaluate_prices(**options)
  end

  def test_above_equal_and_one_cent_below
    result = evaluate([item(unit_price_cents: 901), item(unit_price_cents: 900), item(unit_price_cents: 899)])
    assert_equal 'evaluated', result[:status]
    assert_equal %w[above equal below], (result[:items].map { |row| row[:comparison] })
    assert_equal [2], result[:below_minimum_item_indexes]
  end

  def test_item_and_global_discount_are_both_applied
    result = evaluate([item(quantity: 2, discount_cents: 100)], { discount_cents: 101 })
    row = result[:items].first
    assert_equal 1799, row[:effective_line_cents]
    assert_equal({ numerator: 1799, denominator: 2 }, row[:effective_unit_cents])
    assert_equal 'below', row[:comparison]
    assert_equal 100, row[:item_discount_cents]
    assert_equal 101, row[:global_discount_cents]
    assert_equal result[:financials][:total_cents], row[:effective_line_cents]
  end

  def test_percent_discounts_use_existing_rounding
    result = evaluate([item(unit_price_cents: 1001, discount_percent: '10')], { snapshot: { discount_percent: '10' } })
    assert_equal 100, result[:items].first[:item_discount_cents]
    assert_equal 90, result[:items].first[:global_discount_cents]
    assert_equal 811, result[:items].first[:effective_line_cents]
  end

  def test_remainder_uses_net_weights_and_stable_input_order
    result = evaluate([item, item, item], { discount_cents: 2 })
    assert_equal [1, 1, 0], (result[:items].map { |row| row[:global_discount_cents] })
    assert_equal 2, (result[:items].sum { |row| row[:global_discount_cents] })
    assert_equal [1, 1, 0], (evaluate([item, item, item], { discount_cents: 2 })[:items].map { |row| row[:global_discount_cents] })
  end

  def test_rateio_is_proportional_after_item_discount
    result = evaluate([item(discount_cents: 500), item], { discount_cents: 3 })
    assert_equal [1, 2], (result[:items].map { |row| row[:global_discount_cents] })
  end

  def test_excludes_setup_freight_and_taxes_from_minimum
    result = evaluate([item(setup_fee_cents: 5000)], { discount_cents: 101, shipping_cents: 500, snapshot: { taxes_percent: 10 } })
    assert_equal 899, result[:items].first[:effective_line_cents]
    assert_equal 'below', result[:items].first[:comparison]
    assert_equal 5000, result[:items].first[:setup_fee_cents]
    assert_equal 7039, result[:financials][:total_cents]
  end

  def test_ineligible_items_keep_their_line_price
    result = evaluate([item(eligible_for_global_discount: false), item], { discount_cents: 100 })
    assert_equal [0, 100], (result[:items].map { |row| row[:global_discount_cents] })
    assert_equal %w[above equal], (result[:items].map { |row| row[:comparison] })
  end

  def test_discount_beyond_eligible_base_is_pending_not_clamped_silently
    result = evaluate([item(setup_fee_cents: 5000)], { discount_cents: 1001 })
    assert_equal 'pending', result[:status]
    assert_equal 'global_discount_exceeds_eligible_base', result[:issues].first[:code]
    assert_equal [], result[:items]
    assert_equal 4999, result[:financials][:total_cents]
  end

  def test_zero_net_lines_conserve_zero_global_discount
    result = evaluate([item(discount_cents: 1000), item(discount_cents: 1000)])
    assert_equal [0, 0], (result[:items].map { |row| row[:global_discount_cents] })
    assert_equal %w[below below], (result[:items].map { |row| row[:comparison] })
  end

  def test_does_not_round_unit_price_before_comparison
    row = evaluate([item(quantity: 3, unit_price_cents: 900, discount_cents: 1)])[:items].first
    assert_equal({ numerator: 2699, denominator: 3 }, row[:effective_unit_cents])
    assert_equal 'below', row[:comparison]
  end

  def test_fractional_quantity_uses_existing_three_decimal_precision
    row = evaluate([item(quantity: '1.125', unit_price_cents: 1001)])[:items].first
    assert_equal 1126, row[:gross_line_cents]
    assert_equal({ numerator: 9008, denominator: 9 }, row[:effective_unit_cents])
    assert_equal '1.125', row[:quantity]
  end

  def test_invalid_quantities_fail_with_existing_exception
    [0, -1, 'NaN', 'Infinity', '0.0001'].each do |quantity|
      assert_raises(F::InvalidTerms) { evaluate([item(quantity: quantity)]) }
    end
  end

  def test_missing_or_zero_minimum_requires_a_decision
    [nil, 0].each do |minimum|
      reference = item[:price_reference].merge(minimum_price_cents: minimum)
      result = evaluate([item(price_reference: reference)])
      assert_equal 'pending', result[:status]
      assert_equal 'pending', result[:items].first[:comparison]
    end
    result = evaluate([item(price_reference: item[:price_reference].merge(minimum_price_cents: 0))], {}, zero_minimum: 'authorized_zero')
    assert_equal 'evaluated', result[:status]
    assert_equal 'above', result[:items].first[:comparison]
  end

  def test_explicit_zero_minimum_does_not_turn_missing_minimum_into_zero
    result = evaluate([item(price_reference: item[:price_reference].merge(minimum_price_cents: nil))], {}, zero_minimum: 'authorized_zero')
    assert_equal 'minimum_price_required', result[:issues].first[:code]
  end

  def test_invalid_minimum_or_configuration_is_not_accepted
    [-1, '1.25', 'Infinity', 'bad'].each do |minimum|
      assert_raises(F::InvalidTerms) { evaluate([item(price_reference: item[:price_reference].merge(minimum_price_cents: minimum))]) }
    end
    assert_raises(F::InvalidTerms) { evaluate([item], {}, zero_minimum: 'majority') }
    assert_raises(F::InvalidTerms) { evaluate([item(eligible_for_global_discount: 'false')]) }
  end

  def test_missing_currency_or_mixed_document_currency_has_no_aggregate
    [nil, '', 'brl'].each do |currency|
      result = evaluate([item], { currency: currency })
      assert_equal 'pending', result[:status]
      assert_nil result[:financials]
    end
    result = evaluate([item(currency: 'USD'), item])
    assert_equal 'mixed_document_currency', result[:issues].first[:code]
    assert_nil result[:financials]
  end

  def test_currency_conversion_is_never_inferred
    result = evaluate([item(price_reference: item[:price_reference].merge(currency: 'USD'))])
    assert_equal 'pending', result[:status]
    assert_includes result[:items].first[:issues], 'minimum_currency_mismatch'
  end

  def test_annual_monthly_and_usage_are_not_converted_for_floor
    %w[annual usage one_time].each do |billing|
      result = evaluate([item(billing_model: billing)])
      assert_equal 'pending', result[:items].first[:comparison]
      assert_includes result[:items].first[:issues], 'billing_model_mismatch'
    end
  end

  def test_same_explicit_billing_basis_works_for_all_models
    F::BILLING_MODELS.each do |billing|
      result = evaluate([item(billing_model: billing, price_reference: item[:price_reference].merge(billing_model: billing))])
      assert_equal 'above', result[:items].first[:comparison]
    end
  end

  def test_missing_billing_or_price_unit_is_pending
    [item(billing_model: nil), item(unit_name: nil), item(price_reference: item[:price_reference].merge(unit_name: 'minute')),
     item(price_reference: item[:price_reference].merge(billing_model: nil))].each do |raw|
      assert_equal 'pending', evaluate([raw])[:items].first[:comparison]
    end
  end

  def test_missing_price_and_item_breakdown_are_pending
    [nil, ''].each { |price| assert_equal 'item_price_required', evaluate([item(unit_price_cents: price)])[:issues].first[:code] }
    assert_equal 'item_breakdown_required', evaluate([])[:issues].first[:code]
  end

  def test_oversized_item_discount_is_reported_instead_of_silent_approval
    result = evaluate([item(discount_cents: 1001)])
    assert_equal 'pending', result[:status]
    assert_includes result[:items].first[:issues], 'item_discount_capped_by_legacy_valuation'
  end

  def test_global_legacy_cap_is_reported
    result = evaluate([item], { discount_cents: 1001 })
    assert_equal 'pending', result[:status]
    assert_includes result[:issues].map { |row| row[:code] }, 'global_discount_capped_by_legacy_valuation'
  end

  def test_deal_proposal_and_direct_order_shapes_agree
    deal = item(quantity: 2, discount_cents: 100)
    proposal = item(quantity: 2, discount_percent: 5)
    order = deal.merge(unit_cents: deal[:unit_price_cents],
                       snapshot: { billing_model: deal[:billing_model], unit_name: 'license', price_reference: deal[:price_reference] })
    order.delete(:unit_price_cents)
    order.delete(:price_reference)
    a, b, c = [deal, proposal, order].map { |raw| evaluate([raw], { discount_cents: 101 }) }
    assert_equal a[:items], b[:items]
    assert_equal a[:items], c[:items]
  end

  def test_input_and_legacy_valuation_are_preserved
    attributes = { currency: 'BRL', first_due_date: '2026-10-12', discount_cents: 123, installments_count: 3, payment_condition: 'installments' }
    items = [item(quantity: 3), item(setup_fee_cents: 4000)]
    before = Marshal.dump([attributes, items])
    calculator = F.new(attributes: attributes, items: items)
    legacy = calculator.call
    evaluated = calculator.evaluate_prices
    assert_equal legacy, evaluated[:financials]
    assert_equal legacy, calculator.call
    assert_equal before, Marshal.dump([attributes, items])
    assert_equal legacy[:total_cents], (legacy[:payments].sum { |payment| payment[:value] })
    assert JSON.parse(JSON.generate(evaluated))
  end

  def test_disabled_future_monthly_fee_does_not_change_current_period_floor
    result = evaluate([item(unit_price_cents: 900)], { has_monthly_fee: false })
    assert_equal 'equal', result[:items].first[:comparison]
    assert_equal 0, result[:financials][:monthly_cents]
    assert_equal 900, result[:financials][:total_cents]
  end

  def test_randomized_cent_conservation_without_float_drift
    random = Random.new(20261012)
    100.times do
      items = Array.new(5) { item(unit_price_cents: random.rand(1..100_000), quantity: random.rand(1..5)) }
      gross = items.sum { |raw| raw[:unit_price_cents] * raw[:quantity] }
      discount = random.rand(0..gross)
      result = evaluate(items, { discount_cents: discount })
      assert_equal 'evaluated', result[:status]
      assert_equal discount, (result[:items].sum { |row| row[:global_discount_cents] })
      assert_equal gross - discount, (result[:items].sum { |row| row[:effective_line_cents] })
      assert(result[:items].all? { |row| row[:effective_line_cents] >= 0 })
      assert_equal result[:financials][:total_cents], (result[:items].sum { |row| row[:effective_line_cents] })
    end
  end

  def test_large_integer_prices_keep_their_last_cent
    unit = 9_007_199_254_740_993
    reference = item[:price_reference].merge(minimum_price_cents: unit)
    result = evaluate([item(unit_price_cents: unit, price_reference: reference)], { discount_cents: 1 })
    assert_equal unit - 1, result[:items].first[:effective_line_cents]
    assert_equal 'below', result[:items].first[:comparison]
  end

  def test_authorized_zero_can_be_exactly_zero_without_affecting_next_evaluation
    raw = item(unit_price_cents: 0, price_reference: item[:price_reference].merge(minimum_price_cents: 0))
    assert_equal 'equal', evaluate([raw], {}, zero_minimum: 'authorized_zero')[:items].first[:comparison]
    assert_equal 'pending', evaluate([raw])[:items].first[:comparison]
  end

  def test_reference_preserves_declared_catalogue_metadata_only
    reference = item[:price_reference].merge(company_id: 7, business_unit_id: 9, price_table_id: 3, version: 2,
                                            api_token: 'must-not-appear')
    result = evaluate([item(price_reference: reference)])
    assert_equal 2, result[:items].first[:price_reference][:version]
    assert_equal 7, result[:items].first[:price_reference][:company_id]
    refute_includes JSON.generate(result), 'must-not-appear'
    assert_equal 'must-not-appear', reference[:api_token]
  end

  def test_repeated_calls_do_not_accumulate_issues_or_change_previous_output
    raw = item(price_reference: item[:price_reference].merge(minimum_price_cents: nil))
    attributes = { currency: 'BRL', first_due_date: '2026-10-12' }
    calculator = F.new(attributes: attributes, items: [raw])
    evaluator = JrcCrm::CommercialPriceEvaluation.new(calculator: calculator, attributes: attributes, items: [raw],
                                                     currency: 'BRL', zero_minimum: 'pending')
    first = evaluator.call
    preserved = Marshal.dump(first)
    second = evaluator.call
    assert_equal first, second
    assert_equal 1, second[:issues].length
    assert_equal preserved, Marshal.dump(first)
  end

  def test_snapshot_currency_must_match_even_when_top_level_currency_matches
    [nil, 'BRL'].each do |currency|
      raw = item(currency: currency, snapshot: { currency: 'USD' })
      result = evaluate([raw])
      assert_equal 'pending', result[:status]
      assert_nil result[:financials]
      assert_equal [{ code: 'mixed_document_currency', item_index: 0 }], result[:issues]
    end
  end

  def test_matching_snapshot_currency_is_accepted_without_changing_input
    raw = item(snapshot: { currency: 'BRL' })
    preserved = Marshal.dump(raw)
    result = evaluate([raw])
    assert_equal 'evaluated', result[:status]
    assert_equal 'above', result[:items].first[:comparison]
    assert_equal preserved, Marshal.dump(raw)
  end

  def test_whitespace_only_price_units_do_not_become_comparable
    [item(unit_name: ' '), item(price_reference: item[:price_reference].merge(unit_name: "\t")),
     item(unit_name: ' ', price_reference: item[:price_reference].merge(unit_name: ' '))].each do |raw|
      result = evaluate([raw])
      assert_equal 'pending', result[:status]
      assert_equal 'pending', result[:items].first[:comparison]
      assert_includes result[:items].first[:issues], 'price_unit_required'
    end
  end

  def test_setup_changes_only_the_new_allocation_not_the_legacy_financials
    calculator = F.new(attributes: { currency: 'BRL', first_due_date: '2026-10-12', discount_cents: 30 },
                       items: [item(setup_fee_cents: 5000), item])
    legacy = calculator.call
    result = calculator.evaluate_prices
    allocated = JrcCrm::CommercialItemAllocation.call(items: legacy[:items], discount_cents: 30)
    legacy_discounts = legacy[:items].each_with_index.map { |row, index| row[:one_time_cents] - allocated[index][:revenue_cents] }
    assert_equal [26, 4], legacy_discounts
    assert_equal [15, 15], (result[:items].map { |row| row[:global_discount_cents] })
    assert_equal [985, 985], (result[:items].map { |row| row[:effective_line_cents] })
    assert_equal 6970, legacy[:total_cents]
    assert_equal legacy, result[:financials]
    assert_equal legacy, calculator.call
  end
end
