require 'minitest/autorun'
module JrcRelationship; end
require_relative '../../app/services/jrc_relationship/revenue_metrics'
require_relative '../../app/services/jrc_relationship/adoption_metric'

class RevenueAdoptionTest < Minitest::Test
  def test_usage_growth_requires_baseline_current_and_evidence
    row = { 'metric' => 'adoption', 'baseline' => 10, 'current' => 15, 'evidence' => 'Observed native measurement', 'product_id' => 7 }
    assert_equal 50, JrcRelationship::AdoptionMetric.growth(goals: [row], metric: 'adoption')[:percent]
    assert_equal 7, JrcRelationship::AdoptionMetric.growth(goals: [row], metric: 'adoption')[:product_id]
    [row.merge('baseline' => 0), row.merge('baseline' => 'invalid'), row.merge('evidence' => '')].each do |invalid|
      assert_nil JrcRelationship::AdoptionMetric.growth(goals: [invalid], metric: 'adoption')
    end
  end
  def test_revenue_retention_excludes_new_customers_and_separates_growth_from_loss
    result = JrcRelationship::RevenueMetrics.call(opening: { 1 => 1000, 2 => 1000 }, closing: { 1 => 1500, 2 => 500, 3 => 5000 })
    assert_equal 100, result[:nrr]
    assert_equal 75, result[:gross_retention]
    assert_equal 25, result[:revenue_churn]
    assert_equal 500, result[:revenue_churn_cents]
    assert_equal 2, result[:cohort_customers]
  end

  def test_a_confirmed_zero_is_churn_and_a_missing_closing_measurement_is_unavailable
    assert_equal 0, JrcRelationship::RevenueMetrics.call(opening: { 1 => 1000 }, closing: { 1 => 0 })[:nrr]
    assert_nil JrcRelationship::RevenueMetrics.call(opening: { 1 => 1000 }, closing: {})[:nrr]
    assert_nil JrcRelationship::RevenueMetrics.call(opening: { 1 => 0 }, closing: { 1 => 500 })[:nrr]
    assert_nil JrcRelationship::RevenueMetrics.call(opening: { 1 => 1000 }, closing: { 1 => -1 })[:nrr]
  end

  def test_adoption_requires_real_measurements_and_evidence
    rows = [{ 'metric' => 'active_users', 'target' => 10, 'current' => 5, 'evidence' => 'Customer approved usage report' }]
    result = JrcRelationship::AdoptionMetric.call(goals: rows, metric: 'active_users')
    assert_equal 50, result[:normalized]
    assert_equal 5, result[:raw][0]['current']
    assert_nil JrcRelationship::AdoptionMetric.call(goals: rows.map { |row| row.merge('evidence' => '') }, metric: 'active_users')[:normalized]
    assert_nil JrcRelationship::AdoptionMetric.call(goals: [], metric: 'active_users')[:normalized]
  end

  def test_product_adoption_does_not_mix_measurements_from_other_products
    rows = [{ 'metric' => 'adoption', 'product_id' => 7, 'target' => '10', 'current' => '8', 'evidence' => 'Product 7 report' },
            { 'metric' => 'adoption', 'product_id' => 8, 'target' => 10, 'current' => 1, 'evidence' => 'Product 8 report' }]
    assert_equal 80, JrcRelationship::AdoptionMetric.call(goals: rows, metric: 'adoption', product_id: 7)[:normalized]
    assert_equal 10, JrcRelationship::AdoptionMetric.call(goals: rows, metric: 'adoption', product_id: 8)[:normalized]
  end

  def test_invalid_or_zero_targets_are_not_used_and_results_are_bounded
    row = { 'metric' => 'adoption', 'target' => 10, 'current' => 30, 'evidence' => 'Observed measurement' }
    assert_equal 100, JrcRelationship::AdoptionMetric.call(goals: [row], metric: 'adoption')[:normalized]
    assert_nil JrcRelationship::AdoptionMetric.call(goals: [row.merge('target' => 0)], metric: 'adoption')[:normalized]
    assert_nil JrcRelationship::AdoptionMetric.call(goals: [row.merge('current' => 'invalid')], metric: 'adoption')[:normalized]
  end
end
