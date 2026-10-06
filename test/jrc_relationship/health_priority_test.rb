# Executes without Rails, PostgreSQL, channels, or production data.
require 'minitest/autorun'
require 'date'
module JrcRelationship; end
require_relative '../../app/services/jrc_relationship/health_score'
require_relative '../../app/services/jrc_relationship/priority'

class RelationshipHealthPriorityTest < Minitest::Test
  def observations(values)
    values.transform_values { |value| { raw: value, normalized: value, evidence: 'test source' } }
  end

  def test_health_bands_at_every_boundary
    { nil => 'unavailable', 0 => 'critical', 39.99 => 'critical', 40 => 'risk', 59.99 => 'risk', 60 => 'attention', 79.99 => 'attention', 80 => 'healthy', 100 => 'healthy' }.each do |score, band|
      assert_equal band, JrcRelationship::HealthScore.band(score)
    end
  end

  def test_rel_002_score_below_sixty_is_explainable
    result = JrcRelationship::HealthScore.call(observations: observations('relationship' => 40, 'finance' => 60), weights: { 'relationship' => 75, 'finance' => 25 })
    assert_equal 45, result[:score]
    assert_equal 'risk', result[:band]
    assert_equal 45, result[:factors].sum { |factor| factor[:contribution] }
    assert result[:factors].all? { |factor| factor[:evidence] == 'test source' }
  end

  def test_unavailable_source_is_excluded_from_denominator
    result = JrcRelationship::HealthScore.call(observations: observations('adoption' => nil, 'relationship' => 80), weights: { 'adoption' => 90, 'relationship' => 10 })
    assert_equal 80, result[:score]
    assert_equal 10, result[:coverage_weight]
    assert_nil result[:factors].first[:contribution]
    refute result[:factors].first[:available]
  end

  def test_all_sources_unavailable_is_not_a_zero_or_a_healthy_score
    result = JrcRelationship::HealthScore.call(observations: observations('adoption' => nil), weights: { 'adoption' => 100 })
    assert_nil result[:score]
    assert_equal 'unavailable', result[:band]
  end

  def test_zero_weight_source_does_not_change_the_score
    result = JrcRelationship::HealthScore.call(observations: observations('finance' => 0, 'relationship' => 100), weights: { 'finance' => 0, 'relationship' => 100 })
    assert_equal 100, result[:score]
  end

  def test_normalization_clamps_out_of_range_input
    result = JrcRelationship::HealthScore.call(observations: observations('first' => -50, 'second' => 150), weights: { 'first' => 50, 'second' => 50 })
    assert_equal 50, result[:score]
  end

  def rules
    { 'mrr_priority_ceiling_cents' => 100_000, 'renewal_days' => 120, 'no_contact_days' => 30,
      'priority_health' => 0.4, 'priority_mrr' => 0.2, 'priority_renewal' => 0.2, 'priority_inactivity' => 0.2,
      'critical_threshold' => 40, 'critical_action_priority' => 90, 'ticket_action_priority' => 85, 'detractor_action_priority' => 80, 'health_drop_action_priority' => 70 }
  end

  def data
    { health: { score: 100 }, mrr_cents: 0, days_without_contact: 0, renewal_on: Date.new(2026, 10, 5) + 120, critical_tickets: 0, sla_breached: 0 }
  end

  def priority(attributes = {}, kind: 'health', configuration: rules, **values)
    JrcRelationship::Priority.call(data: data.merge(attributes).merge(values), rules: configuration, kind: kind, today: Date.new(2026, 10, 5))
  end

  def test_health_drop_uses_an_explainable_configured_priority_floor
    result = priority({}, kind: 'health_drop')
    assert_equal 70, result[:score]
    assert_equal 70, result[:factors]['urgency_floor']
  end

  def test_cs_03_critical_health_has_configured_urgency_floor
    result = priority(health: { score: 20 })
    assert_equal 90, result[:score]
    assert_equal 90, result[:factors]['urgency_floor']
  end

  def test_rel_003_critical_ticket_has_priority_with_evidence
    assert_equal 85, priority({ critical_tickets: 1 }, kind: 'ticket')[:score]
  end

  def test_rel_004_and_cs_05_detractor_is_urgent
    assert_equal 80, priority({}, kind: 'satisfaction')[:score]
  end

  def test_urgency_is_configurable
    assert_equal 95, priority({ health: { score: 20 } }, configuration: rules.merge('critical_action_priority' => 95))[:score]
  end

  def test_cs_04_sixty_day_renewal_affects_priority
    far = priority({}, kind: 'renewal')[:score]
    near = priority({ renewal_on: Date.new(2026, 12, 4) }, kind: 'renewal')[:score]
    assert_operator near, :>, far
    assert_equal 50, priority({ renewal_on: Date.new(2026, 12, 4) }, kind: 'renewal')[:factors]['renewal'][:normalized]
  end

  def test_cs_02_inactivity_contribution_increases_at_thirty_days
    assert_operator priority(days_without_contact: 30)[:score], :>, priority(days_without_contact: 0)[:score]
  end

  def test_missing_health_is_not_fabricated_as_critical
    result = priority(health: { score: nil }, mrr_cents: nil, renewal_on: nil, days_without_contact: nil)
    assert_equal 0, result[:score]
    refute result[:factors]['health'][:available]
    assert_nil result[:factors]['health'][:contribution]
  end

  def test_priority_factors_sum_to_weighted_score_without_urgency
    result = priority(health: { score: 50 }, mrr_cents: 50_000, days_without_contact: 15)
    assert_equal result[:score], result[:factors].values.select { |value| value.is_a?(Hash) }.sum { |factor| factor[:contribution].to_f }.round
  end
  def test_manual_priority_survives_refresh_while_factors_follow_current_signals
    original = JrcRelationship::Priority.call(data: data, rules: rules, kind: 'health', today: Date.new(2026, 10, 5), manual_priority: 88)
    updated = JrcRelationship::Priority.call(data: data.merge(health: { score: 20 }), rules: rules, kind: 'health', today: Date.new(2026, 10, 5), manual_priority: 88)
    assert_equal 88, original[:score]
    assert_equal 88, updated[:score]
    refute_equal original[:factors]['health'], updated[:factors]['health']
    assert_equal 90, updated[:factors]['urgency_floor']
  end

  def test_manual_zero_priority_is_not_replaced_by_calculated_urgency
    result = JrcRelationship::Priority.call(data: data.merge(health: { score: 20 }), rules: rules, kind: 'health', today: Date.new(2026, 10, 5), manual_priority: 0)
    assert_equal 0, result[:score]
    assert_equal 90, result[:factors]['urgency_floor']
  end

end
