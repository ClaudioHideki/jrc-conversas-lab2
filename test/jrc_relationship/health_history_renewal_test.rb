require 'minitest/autorun'
require 'date'
module JrcRelationship; end
require_relative '../../app/services/jrc_relationship/health_change'
require_relative '../../app/services/jrc_relationship/renewal_window'

class RelationshipHealthHistoryRenewalTest < Minitest::Test
  def test_rel_04_preserves_zero_score_and_explains_weight_evidence_and_contribution
    old = { score: 0, config_version: 1, factors: [{ factor: 'finance', normalized: 0, weight: 50, contribution: 0, evidence: 'Overdue invoice' }] }
    now = { score: 50, config_version: 2, factors: [{ factor: 'finance', normalized: 100, weight: 50, contribution: 50, evidence: 'Invoice paid' }] }
    result = JrcRelationship::HealthChange.call(previous: old, current: now)
    assert_equal 50, result[:delta]
    assert result[:configuration_changed]
    assert_equal 'Overdue invoice', result[:factors][0][:before][:evidence]
    assert_equal 'Invoice paid', result[:factors][0][:after][:evidence]
    assert_equal 50, result[:factors][0][:delta]
  end

  def test_rel_04_does_not_invent_history_when_no_previous_score_exists
    assert_nil JrcRelationship::HealthChange.call(previous: nil, current: { score: 80 })
    assert_nil JrcRelationship::HealthChange.call(previous: { score: nil }, current: { score: 80 })
  end

  def test_rel_04_includes_removed_factors_and_changed_raw_evidence
    old = { score: 70, factors: [{ 'factor' => 'finance', 'raw' => 200, 'normalized' => 40 }, { 'factor' => 'adoption', 'normalized' => 100 }] }
    now = { score: 60, factors: [{ factor: 'finance', raw: 100, normalized: 40 }] }
    rows = JrcRelationship::HealthChange.call(previous: old, current: now)[:factors]
    assert_equal %w[finance adoption], rows.map { |row| row[:factor] }
    assert_equal 100, rows[0][:after][:raw]
    assert_nil rows[1][:after]
  end

  def test_rel_04_unchanged_factors_do_not_fabricate_causes
    snapshot = { score: 70, config_scope_key: 'account', config_version: 1, factors: [{ factor: 'finance', normalized: 70 }] }
    result = JrcRelationship::HealthChange.call(previous: snapshot, current: snapshot)
    assert_equal 0, result[:delta]
    assert_empty result[:factors]
    refute result[:configuration_changed]
  end

  def test_rel_09_every_boundary_belongs_to_exactly_one_window
    today = Date.new(2026, 10, 6)
    { -1 => 'overdue', 0 => '15', 15 => '15', 16 => '30', 30 => '30', 31 => '60', 60 => '60',
      61 => '90', 90 => '90', 91 => '120', 120 => '120', 121 => 'later' }.each do |days, key|
      assert_equal key, JrcRelationship::RenewalWindow.key(today + days, today: today)
    end
    assert_nil JrcRelationship::RenewalWindow.key(nil, today: today)
  end

  def test_rel_09_query_ranges_match_classification_for_each_day
    today = Date.new(2026, 10, 6)
    relation = Object.new
    def relation.where(renewal_on:); renewal_on; end
    ranges = JrcRelationship::RenewalWindow::WINDOWS.keys.to_h do |key|
      [key, JrcRelationship::RenewalWindow.scope(relation, key, today: today)]
    end
    (-10..150).each do |days|
      date = today + days
      assert_equal [JrcRelationship::RenewalWindow.key(date, today: today)], ranges.select { |_, range| range.cover?(date) }.keys
    end
  end

  def test_invalid_window_is_rejected_instead_of_broadening_scope
    assert_raises(KeyError) { JrcRelationship::RenewalWindow.scope(nil, 'invalid', today: Date.new(2026, 10, 6)) }
  end
end
