require 'minitest/autorun'
module JrcRelationship; end
require_relative '../../app/services/jrc_relationship/playbook_conditions'

class PlaybookConditionsTest < Minitest::Test
  def test_requires_all_conditions_and_uses_actual_health
    conditions = [{ 'field' => 'health_score', 'operator' => 'lt', 'value' => 60 },
                  { 'field' => 'mrr_cents', 'operator' => 'gte', 'value' => 100_000 }]
    assert JrcRelationship::PlaybookConditions.match?(conditions, { health: { score: 42 }, mrr_cents: 100_000 })
    refute JrcRelationship::PlaybookConditions.match?(conditions, { health: { score: 80 }, mrr_cents: 100_000 })
    refute JrcRelationship::PlaybookConditions.match?(conditions, { health: { score: 42 }, mrr_cents: 10_000 })
  end

  def test_missing_evidence_never_becomes_zero
    condition = [{ 'field' => 'csat', 'operator' => 'lt', 'value' => 3 }]
    refute JrcRelationship::PlaybookConditions.match?(condition, { csat: nil })
    assert JrcRelationship::PlaybookConditions.match?(condition, { csat: 2 })
  end

  def test_rejects_unknown_fields_operators_and_nonfinite_values
    refute JrcRelationship::PlaybookConditions.valid?([{ 'field' => 'secret', 'operator' => 'eq', 'value' => 1 }])
    refute JrcRelationship::PlaybookConditions.valid?([{ 'field' => 'nps', 'operator' => 'eval', 'value' => 1 }])
    refute JrcRelationship::PlaybookConditions.valid?([{ 'field' => 'nps', 'operator' => 'eq', 'value' => Float::INFINITY }])
    refute JrcRelationship::PlaybookConditions.valid?(nil)
  end

  def test_supports_empty_and_bounded_condition_lists
    assert JrcRelationship::PlaybookConditions.match?([], {})
    condition = { 'field' => 'nps', 'operator' => 'eq', 'value' => -100 }
    assert JrcRelationship::PlaybookConditions.valid?(Array.new(20, condition))
    refute JrcRelationship::PlaybookConditions.valid?(Array.new(21, condition))
  end

  def test_all_numeric_operators
    { 'lt' => 6, 'lte' => 5, 'eq' => 5, 'gte' => 5, 'gt' => 4 }.each do |operator, target|
      assert JrcRelationship::PlaybookConditions.match?([{ 'field' => 'csat', 'operator' => operator, 'value' => target }], { csat: 5 })
    end
  end
  def test_native_segment_product_and_unit_conditions_require_matching_real_ids
    conditions = [{ 'field'=>'segment_id', 'operator'=>'eq', 'value'=>2 },
      { 'field'=>'product_id', 'operator'=>'eq', 'value'=>9 }, { 'field'=>'business_unit_id', 'operator'=>'eq', 'value'=>3 }]
    signals = { segment_id:'2', products:[{ id:9 }], business_unit_id:3 }
    assert JrcRelationship::PlaybookConditions.match?(conditions, signals)
    refute JrcRelationship::PlaybookConditions.match?(conditions, signals.merge(business_unit_id:4))
    refute JrcRelationship::PlaybookConditions.match?(conditions, signals.merge(products:[]))
    refute JrcRelationship::PlaybookConditions.valid?([{ 'field'=>'product_id', 'operator'=>'lt', 'value'=>9 }])
    refute JrcRelationship::PlaybookConditions.valid?([{ 'field'=>'product_id', 'operator'=>'eq', 'value'=>9.5 }])
    refute JrcRelationship::PlaybookConditions.valid?([{ 'field'=>'product_id', 'operator'=>'eq', 'value'=>0 }])
  end

end
