# frozen_string_literal: true
# Run with Ruby alone. Real rules/calendar arithmetic, injected FIXED-OFFSET zone only.
# NOT Rails/RSpec/PostgreSQL/TZInfo integration or HTTP validation.
require 'minitest/autorun'
require 'time'
module JrcServiceDesk; end
ROOT = File.expand_path('../..', __dir__) unless defined?(ROOT)
%w[input canonical_json lifecycle_rules lifecycle_dependency_error snapshot_calendar kpi_counts].each do |name|
  require File.join(ROOT, 'app/services/jrc_service_desk', name)
end

module LifecycleTestData
  def definition
    { 'schema_version' => 1, 'transitions' => [{ 'key' => 'resolve', 'action' => 'resolve', 'from_status_ids' => [1], 'to_status_id' => 2,
      'requirements' => { 'note' => true, 'solution' => true, 'evidence' => true, 'classification' => true,
        'fields' => { 'accepted' => { 'label' => 'Verified fixture', 'type' => 'boolean', 'required' => true, 'equals' => true } } },
      'clocks' => { 'first_response' => 'stop', 'resolution' => 'complete' }, 'end_pause' => true }],
      'pause_reasons' => [{ 'code' => 'waiting_customer', 'name' => 'Fixture', 'status_ids' => [3], 'clocks' => ['resolution'] }],
      'reopen' => { 'allowed' => true, 'window_seconds' => 3600, 'anchor_action' => 'resolve', 'expired' => 'deny',
        'sla_cycle' => 'continue_cycle', 'inactive_time' => 'exclude', 'resume_clocks' => ['resolution'], 'new_cycle_snapshot' => 'same_snapshot' },
      'sla' => { 'mode' => 'calendar_snapshot', 'initial_start' => 'opened_at' } }
  end
  def valid_payload
    { 'note' => 'Verified', 'solution' => 'Fix fixture', 'evidence_note_ids' => [7], 'fields' => { 'accepted' => true } }
  end
  def calendar_data
    { 'format' => 'jrc-sd-snapshot-calendar-v1', 'weekly' => (1..7).to_h { |day| [day.to_s, day <= 5 ? [['09:00', '17:00']] : []] }, 'holidays' => [], 'exceptions' => {} }
  end
  FixedOffset = Struct.new(:seconds) do
    def to_local(time)
      time.getlocal(seconds)
    end
    def local_to_utc(local, dst)
      raise 'DST must not be inferred' unless dst.nil?
      local - seconds
    end
  end
  def calendar(data = calendar_data, offset: -10800, zone: nil)
    JrcServiceDesk::SnapshotCalendar.new(timezone: 'Test/ExplicitZone', conditions: data, zone: zone || FixedOffset.new(offset))
  end
  def instant(text)
    Time.iso8601(text)
  end
end

class LifecycleRulesIsolatedTest < Minitest::Test
  include LifecycleTestData
  def test_complete_explicit_definition_and_requirements
    rules = JrcServiceDesk::LifecycleRules.new(definition)
    assert rules.validate_payload!(rules.rule('resolve'), valid_payload, classified: true)
    assert_equal ['resolution'], rules.reason('waiting_customer', 3)['clocks']
  end
  def test_no_rule_no_reason_no_automatic_waiting_pause
    rules = JrcServiceDesk::LifecycleRules.new(definition)
    assert_raises(ArgumentError) { rules.rule('close') }
    assert_raises(ArgumentError) { rules.reason('unknown', 3) }
    assert_raises(ArgumentError) { rules.reason('waiting_customer', 4) }
    d = definition; d['pause_reasons'][0]['clocks'] = []
    assert_equal [], JrcServiceDesk::LifecycleRules.new(d).reason('waiting_customer', 3)['clocks']
    d['pause_reasons'][0].delete('clocks')
    assert_raises(ArgumentError) { JrcServiceDesk::LifecycleRules.new(d) }
  end
  def test_all_top_level_configuration_is_explicit
    definition.keys.each do |key|
      d = definition; d.delete(key)
      assert_raises(ArgumentError) { JrcServiceDesk::LifecycleRules.new(d) }
    end
    assert_raises(ArgumentError) { JrcServiceDesk::LifecycleRules.new(definition.merge('global_admin' => true)) }
  end
  def test_unknown_and_duplicate_transitions_are_rejected
    %w[delete run_script].each do |action|
      d = definition; d['transitions'][0]['action'] = action
      assert_raises(ArgumentError) { JrcServiceDesk::LifecycleRules.new(d) }
    end
    d = definition; d['transitions'] << d['transitions'][0].dup
    assert_raises(ArgumentError) { JrcServiceDesk::LifecycleRules.new(d) }
  end
  def test_ids_are_not_coerced_into_authorization
    [nil, 0, -1, '1', '1 OR 1=1', [1], {}, true].each do |bad|
      d = definition; d['transitions'][0]['to_status_id'] = bad
      assert_raises(ArgumentError) { JrcServiceDesk::LifecycleRules.new(d) }
    end
  end
  def test_internal_transition_cannot_fabricate_first_response
    d = definition; d['transitions'][0]['clocks']['first_response'] = 'complete'
    assert_raises(ArgumentError) { JrcServiceDesk::LifecycleRules.new(d) }
    d = definition; d['transitions'][0]['action'] = 'close'
    assert_raises(ArgumentError) { JrcServiceDesk::LifecycleRules.new(d) }
  end
  def test_no_sla_requires_explicit_no_clock_effects
    d = definition; d['sla']['mode'] = 'not_applicable'
    assert_raises(ArgumentError) { JrcServiceDesk::LifecycleRules.new(d) }
    d['transitions'][0]['clocks'].transform_values! { 'keep' }; d['pause_reasons'][0]['clocks'] = []
    assert JrcServiceDesk::LifecycleRules.new(d)
  end
  def test_requirements_are_not_satisfied_by_missing_fields
    rules = JrcServiceDesk::LifecycleRules.new(definition); rule = rules.rule('resolve')
    valid_payload.keys.each do |key|
      p = valid_payload; p.delete(key)
      assert_raises(ArgumentError) { rules.validate_payload!(rule, p, classified: true) }
    end
    assert_raises(ArgumentError) { rules.validate_payload!(rule, valid_payload, classified: false) }
  end
  def test_equality_gate_rejects_false_without_arbitrary_evaluation
    rules = JrcServiceDesk::LifecycleRules.new(definition)
    p = valid_payload; p['fields']['accepted'] = false
    assert_raises(ArgumentError) { rules.validate_payload!(rules.rule('resolve'), p, classified: true) }
    d = definition; d['transitions'][0]['requirements']['fields']['accepted']['equals'] = 'eval(true)'
    assert_raises(ArgumentError) { JrcServiceDesk::LifecycleRules.new(d) }
  end
  def test_text_evidence_and_field_bounds
    rules = JrcServiceDesk::LifecycleRules.new(definition); rule = rules.rule('resolve')
    [{ 'note' => ' ' }, { 'solution' => 'x' * 20001 }, { 'evidence_note_ids' => [7, 7] },
     { 'evidence_note_ids' => [0] }, { 'fields' => { 'unknown' => 'unsafe' } }, { 'evidence_note_ids' => (1..51).to_a }].each do |override|
      assert_raises(ArgumentError) { rules.validate_payload!(rule, valid_payload.merge(override), classified: true) }
    end
  end
  def test_prototype_like_keys_rejected_in_configuration
    %w[__proto__ constructor prototype].each do |key|
      d = definition; d['transitions'][0]['requirements']['fields'] = { key => { 'label' => 'Bad', 'type' => 'text', 'required' => false } }
      assert_raises(ArgumentError) { JrcServiceDesk::LifecycleRules.new(d) }
    end
  end
  def test_reopening_exact_boundary_is_configured_not_fixed
    rules = JrcServiceDesk::LifecycleRules.new(definition); anchor = instant('2026-09-28T12:00:00Z')
    assert_equal 'continue_cycle', rules.reopen_check!(now: anchor + 3600, anchor: anchor)['sla_cycle']
    assert_raises(ArgumentError) { rules.reopen_check!(now: anchor + 3600.001, anchor: anchor) }
    assert_raises(ArgumentError) { rules.reopen_check!(now: anchor - 1, anchor: anchor) }
    assert_raises(ArgumentError) { rules.reopen_check!(now: anchor, anchor: nil) }
  end
  def test_both_cycle_choices_and_expiry_behavior_are_explicit
    %w[continue_cycle new_cycle].product(%w[count exclude], %w[same_snapshot latest_snapshot], %w[deny require_new_ticket]).each do |cycle, inactive, snapshot, expiry|
      d = definition; d['reopen'].merge!('sla_cycle' => cycle, 'inactive_time' => inactive, 'new_cycle_snapshot' => snapshot, 'expired' => expiry)
      r = JrcServiceDesk::LifecycleRules.new(d); anchor = Time.at(0)
      assert_equal cycle, r.reopen_check!(now: anchor + 1, anchor: anchor)['sla_cycle']
      error = assert_raises(ArgumentError) { r.reopen_check!(now: anchor + 9999, anchor: anchor) }
      assert_includes error.message, expiry == 'deny' ? 'expired' : 'separate ticket'
    end
  end
  def test_reopening_configuration_cannot_be_omitted_or_implicitly_allowed
    %w[window_seconds anchor_action expired sla_cycle inactive_time resume_clocks new_cycle_snapshot].each do |key|
      d = definition; d['reopen'].delete(key)
      assert_raises(ArgumentError) { JrcServiceDesk::LifecycleRules.new(d) }
    end
    d = definition; d['reopen']['allowed'] = false
    r = JrcServiceDesk::LifecycleRules.new(d)
    assert_raises(ArgumentError) { r.reopen_check!(now: Time.at(1), anchor: Time.at(0)) }
  end
end

class CalendarIsolatedTest < Minitest::Test
  include LifecycleTestData
  def test_real_interval_intersection_in_explicit_offset
    c = calendar
    assert_equal 7200, c.elapsed(instant('2026-09-28T13:00:00Z'), instant('2026-09-28T15:00:00Z'))
    assert_equal 0, c.elapsed(instant('2026-09-28T10:00:00Z'), instant('2026-09-28T11:00:00Z'))
    assert_equal 28800, c.elapsed(instant('2026-09-28T00:00:00Z'), instant('2026-09-29T00:00:00Z'))
  end
  def test_deadline_skips_night_weekend_and_explicit_holiday
    d = calendar_data; d['holidays'] = ['2026-09-28']
    assert_equal instant('2026-09-29T13:00:00Z'), calendar(d).advance(instant('2026-09-25T19:00:00Z'), 7200)
  end
  def test_exception_overrides_holiday_and_regular_workday
    d = calendar_data; d['holidays'] = ['2026-09-28']; d['exceptions'] = { '2026-09-28' => [['10:00','12:00']] }
    assert_equal 7200, calendar(d).elapsed(instant('2026-09-28T00:00:00Z'), instant('2026-09-29T00:00:00Z'))
    d['exceptions']['2026-09-28'] = []
    assert_equal 0, calendar(d).elapsed(instant('2026-09-28T00:00:00Z'), instant('2026-09-29T00:00:00Z'))
  end
  def test_lunch_intervals_and_arbitrary_explicit_offset
    d = calendar_data; d['weekly']['1'] = [['09:00','12:00'], ['13:00','17:00']]
    c = calendar(d, offset: 19800)
    assert_equal 7 * 3600, c.elapsed(instant('2026-09-28T00:00:00Z'), instant('2026-09-29T00:00:00Z'))
    assert_equal instant('2026-09-28T08:30:00Z'), c.advance(instant('2026-09-28T05:30:00Z'), 7200)
  end
  def test_missing_calendars_and_legacy_shapes_fail_instead_of_fallback
    [{}, { 'weekdays' => [1,2,3,4,5] }, calendar_data.merge('format' => 'unknown')].each do |d|
      assert_raises(JrcServiceDesk::LifecycleDependencyError) { calendar(d) }
    end
    d = calendar_data; d['weekly'].delete('7')
    assert_raises(JrcServiceDesk::LifecycleDependencyError) { calendar(d) }
  end
  def test_invalid_overlaps_overnight_and_dates_are_not_guessed
    [[['09:00','13:00'],['12:00','17:00']], [['22:00','06:00']], [['9:00','17:00']], [['24:00','24:00']]].each do |intervals|
      d = calendar_data; d['weekly']['1'] = intervals
      assert_raises(JrcServiceDesk::LifecycleDependencyError) { calendar(d) }
    end
    d = calendar_data; d['holidays'] = ['2026-02-30']
    assert_raises(JrcServiceDesk::LifecycleDependencyError) { calendar(d) }
  end
  def test_no_configured_work_and_negative_durations_rejected
    d = calendar_data; d['weekly'].transform_values! { [] }
    assert_raises(JrcServiceDesk::LifecycleDependencyError) { calendar(d) }
    [0,-1,Float::INFINITY,Float::NAN].each { |v| assert_raises(ArgumentError) { calendar.advance(Time.now, v) } }
    assert_raises(ArgumentError) { calendar.elapsed(Time.at(5), Time.at(0)) }
  end
  def test_ambiguous_local_time_error_is_not_silently_resolved
    zone = FixedOffset.new(0)
    def zone.local_to_utc(_time, _dst); raise 'Injected ambiguity - not TZInfo integration'; end
    assert_raises(JrcServiceDesk::LifecycleDependencyError) { calendar(zone: zone).advance(instant('2026-09-28T09:00:00Z'), 60) }
  end
  def test_elapsed_is_additive_and_advance_inverts_work_time_for_many_intervals
    c = calendar
    start = instant('2026-09-25T12:00:00Z')
    [1,60,3600,7200,28800,60000,130000].each do |budget|
      due = c.advance(start, budget)
      assert_in_delta budget, c.elapsed(start, due), 0.000001
    end
    (1..10).each do |day|
      middle = start + day * 86400
      last = middle + 86400
      assert_in_delta c.elapsed(start, last), c.elapsed(start, middle) + c.elapsed(middle, last), 0.000001
    end
  end
  def test_kpi_partition_is_not_a_visual_counter
    groups = { [1,'Fixture open','open'] => 8, [2,'Fixture working','open'] => 12, [3,'Fixture done','resolved'] => 7 }
    first = JrcServiceDesk::KpiCounts.call(groups)
    assert_equal 27, first[:total]; assert_equal 20, first[:active]
    groups[[1,'Fixture open','open']] -= 1; groups[[3,'Fixture done','resolved']] += 1
    after = JrcServiceDesk::KpiCounts.call(groups)
    assert_equal 27, after[:total]; assert_equal 19, after[:active]
    assert_equal after[:total], after[:phases].values.sum
  end
end
