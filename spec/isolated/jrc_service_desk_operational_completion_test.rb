# frozen_string_literal: true

# Executes pure production classes; deliberately NOT a Rails/PostgreSQL/E2E gate.
require 'minitest/autorun'
module JrcServiceDesk; end
%w[canonical_json input ticket_search operational_rule_contract operational_rule_matcher operational_csv recurrence_grouping].each do |file|
  require_relative "../../app/services/jrc_service_desk/#{file}"
end

class ServiceDeskOperationalCompletionTest < Minitest::Test
  Contract = JrcServiceDesk::OperationalRuleContract
  Matcher = JrcServiceDesk::OperationalRuleMatcher
  Json = JrcServiceDesk::CanonicalJson

  def rule(key = 'office', rank = 0, match = { 'inbox_id' => 3 }, output = { 'queue_id' => 7 })
    { 'key' => key, 'precedence' => rank, 'match' => match, 'output' => output }
  end

  def snapshot
    { 'source_system' => 'contract-registry', 'source_reference' => 'test-only', 'source_version' => '1',
      'policy_key' => 'sla', 'policy_version' => '1', 'calendar_key' => 'business', 'calendar_version' => '1',
      'timezone' => 'UTC', 'calendar_scope' => 'unit', 'contract_conditions' => {},
      'calendar_conditions' => {}, 'policy_conditions' => { 'clock_budgets_seconds' => { 'first_response' => 60, 'resolution' => 600 } } }
  end

  def deadline
    { 'executor_account_user_id' => 1, 'after_due_seconds' => 0, 'new_due_seconds' => 60,
      'target' => { 'approver_account_user_id' => 2 }, 'reason' => 'Published escalation policy' }
  end

  def recurrence
    { 'window_days' => 30, 'minimum_occurrences' => 2, 'group_by' => %w[company_id normalized_title] }
  end

  def test_number_search_is_exact_bounded_and_accepts_hash_prefix
    { '1' => 1, '#27' => 27, '  #27 ' => 27, '9223372036854775807' => 9_223_372_036_854_775_807 }.each do |text, value|
      assert_equal value, JrcServiceDesk::TicketSearch.identifier(text)
    end
    ['', '0', '-2', '+3', '1.0', '1e2', '01', '##3', 'SD-249', '9223372036854775808', '3 OR TRUE', "3\nOR TRUE"].each do |value|
      assert_nil JrcServiceDesk::TicketSearch.identifier(value), value.inspect
    end
  end

  def test_search_rejects_invalid_types_and_large_input_without_touching_relation
    [nil, [], {}, 4, 'a' * 201].each do |value|
      assert_raises(ArgumentError) { JrcServiceDesk::TicketSearch.apply(Object.new, value) }
    end
    relation = Object.new
    assert_same relation, JrcServiceDesk::TicketSearch.apply(relation, '   ')
  end

  def test_all_rule_families_are_finite
    %w[routing priority_matrix sla_selection approval_deadline recurrence].each { |kind| assert_includes Contract::KINDS, kind }
    [nil, 'ruby', 'http', 'shell'].each { |kind| assert_raises(ArgumentError) { Contract.validate!(kind, {}) } }
  end

  def test_routing_requires_explicit_nonnegative_precedence_and_target
    row = rule
    assert_same row, Contract.validate!('routing', 'rules' => [row])['rules'][0]
    %w[key precedence match output].each do |field|
      invalid = rule.reject { |key, _| key == field }
      assert_raises(ArgumentError) { Contract.validate!('routing', 'rules' => [invalid]) }
    end
    [-1, 1_000_001, 1.5, '2', nil].each do |rank|
      assert_raises(ArgumentError) { Contract.validate!('routing', 'rules' => [rule('x', rank)]) }
    end
    [0, -2, '3', nil, 2**63].each do |id|
      assert_raises(ArgumentError) { Contract.validate!('routing', 'rules' => [rule('x', 1, {}, 'queue_id' => id)]) }
    end
  end

  def test_rule_keys_unknown_fields_and_counts
    [[], Array.new(101) { |i| rule("r#{i}") }].each { |rows| assert_raises(ArgumentError) { Contract.validate!('routing', 'rules' => rows) } }
    assert_raises(ArgumentError) { Contract.validate!('routing', 'rules' => [rule, rule]) }
    ['', 'x y', '../x', 'x' * 65].each { |key| assert_raises(ArgumentError) { Contract.validate!('routing', 'rules' => [rule(key)]) } }
    assert_raises(ArgumentError) { Contract.validate!('routing', 'rules' => [rule.merge('script' => 'danger')]) }
    assert_raises(ArgumentError) { Contract.validate!('routing', 'rules' => [rule], 'execute' => true) }
  end

  def test_match_predicates_cannot_execute_expressions
    fields = { 'inbox_id' => 1, 'company_id' => 2, 'contract_id' => 3, 'category_id' => 4, 'service_id' => 5,
               'priority_id' => 6, 'ticket_type_id' => 7, 'channel_type' => 'Channel::Whatsapp', 'impact' => 'major', 'urgency' => 'now' }
    assert Contract.predicates!(fields)
    [{ 'query' => 'x' }, { 'channel_type' => 'Kernel' }, { 'channel_type' => 'Channel::X;eval' }, { 'impact' => 'a b' }].each do |invalid|
      assert_raises(ArgumentError) { Contract.predicates!(invalid) }
    end
  end

  def test_matrix_requires_both_axes_and_priority
    output = { 'priority_id' => 8 }
    valid = rule('major-urgent', 10, { 'impact' => 'major', 'urgency' => 'urgent' }, output)
    assert Contract.validate!('priority_matrix', 'rules' => [valid])
    %w[impact urgency].each do |field|
      invalid = Marshal.load(Marshal.dump(valid))
      invalid['match'].delete(field)
      assert_raises(ArgumentError) { Contract.validate!('priority_matrix', 'rules' => [invalid]) }
    end
    assert_raises(ArgumentError) { Contract.validate!('priority_matrix', 'rules' => [rule]) }
  end

  def test_matcher_uses_all_predicates_exactly_and_explicit_precedence
    broad = rule('broad', 20, {}, 'queue_id' => 2)
    exact = rule('exact', 10, { 'inbox_id' => 1, 'company_id' => 2 }, 'queue_id' => 3)
    assert_same exact, Matcher.call([broad, exact], 'inbox_id' => 1, 'company_id' => 2)
    assert_same broad, Matcher.call([exact, broad], 'inbox_id' => 1)
    assert_same broad, Matcher.call([exact, broad], 'inbox_id' => '1', 'company_id' => 2)
    assert_nil Matcher.call([exact], 'inbox_id' => nil, 'company_id' => 2)
    assert_nil Matcher.call([], {})
  end

  def test_matching_ties_are_not_broken_by_order_or_specificity
    first = rule('first', 5, {})
    second = rule('second', 5, 'inbox_id' => 1)
    [[first, second], [second, first]].each do |rows|
      assert_raises(Matcher::Ambiguous) { Matcher.call(rows, 'inbox_id' => 1) }
    end
    assert_same first, Matcher.call([first, second], 'inbox_id' => 2)
  end

  def test_no_match_never_invents_a_default_target
    assert_nil Matcher.call([rule], 'inbox_id' => 100)
    assert_nil Matcher.call([rule], {})
  end

  def test_snapshot_requires_provenance_and_explicit_clock_budgets
    assert Contract.snapshot!(snapshot)
    snapshot.keys.each do |field|
      invalid = snapshot
      invalid.delete(field)
      assert_raises(ArgumentError, field) { Contract.snapshot!(invalid) }
    end
    %w[first_response resolution].each do |field|
      invalid = snapshot
      invalid['policy_conditions']['clock_budgets_seconds'].delete(field)
      assert_raises(ArgumentError) { Contract.snapshot!(invalid) }
    end
    invalid = snapshot
    invalid['policy_conditions']['clock_budgets_seconds']['attendance'] = 30
    assert Contract.snapshot!(invalid)
    [0, -1, 1.5, '60', 2**53].each do |budget|
      invalid = snapshot
      invalid['policy_conditions']['clock_budgets_seconds']['resolution'] = budget
      assert_raises(ArgumentError) { Contract.snapshot!(invalid) }
    end
  end

  def test_snapshot_rejects_nested_credentials_and_prototype_keys
    %w[password api_key access_token refresh_token secret credential Authorization __proto__ constructor prototype].each do |key|
      invalid = snapshot
      invalid['contract_conditions']['nested'] = [{ key => 'not-a-real-secret' }]
      assert_raises(ArgumentError, key) { Contract.snapshot!(invalid) }
    end
    invalid = snapshot
    invalid['calendar_scope'] = 'automatic'
    assert_raises(ArgumentError) { Contract.snapshot!(invalid) }
  end

  def test_deadline_has_no_implicit_executor_or_target
    assert Contract.validate!('approval_deadline', deadline)
    deadline.keys.each do |key|
      invalid = deadline
      invalid.delete(key)
      assert_raises(ArgumentError) { Contract.validate!('approval_deadline', invalid) }
    end
    [{}, { 'approver_role' => 'CEO' }, { 'approver_account_user_id' => 2, 'approver_role' => 'agent' }].each do |target|
      assert_raises(ArgumentError) { Contract.validate!('approval_deadline', deadline.merge('target' => target)) }
    end
    %w[agent administrator].each do |role|
      assert Contract.validate!('approval_deadline', deadline.merge('target' => { 'approver_role' => role }))
    end
    [nil, true, 0, -1].each do |value|
      assert_raises(ArgumentError) { Contract.validate!('approval_deadline', deadline.merge('executor_account_user_id' => value)) }
    end
  end

  def test_deadline_grace_and_new_due_boundaries
    [-1, 31_536_001, '0'].each { |value| assert_raises(ArgumentError) { Contract.deadline!(deadline.merge('after_due_seconds' => value)) } }
    [0, -1, 31_536_001, '60'].each { |value| assert_raises(ArgumentError) { Contract.deadline!(deadline.merge('new_due_seconds' => value)) } }
    ['', ' ' * 3, 'x' * 1001].each { |value| assert_raises(ArgumentError) { Contract.deadline!(deadline.merge('reason' => value)) } }
  end

  def test_recurrence_thresholds_and_dimensions_are_explicit
    assert Contract.validate!('recurrence', recurrence)
    [0, 367, '30'].each { |value| assert_raises(ArgumentError) { Contract.recurrence!(recurrence.merge('window_days' => value)) } }
    [1, 1001, '3'].each { |value| assert_raises(ArgumentError) { Contract.recurrence!(recurrence.merge('minimum_occurrences' => value)) } }
    [[], %w[company_id company_id], ['sql'], 'company_id'].each do |value|
      assert_raises(ArgumentError) { Contract.recurrence!(recurrence.merge('group_by' => value)) }
    end
  end

  def test_recurrence_counts_distinct_tickets_not_duplicate_rows
    rows = [row(1), row(2), row(2), row(3, 'company_id' => 7)]
    groups = JrcServiceDesk::RecurrenceGrouping.call(rows, recurrence)
    assert_equal 1, groups.size
    assert_equal %w[1 2], groups[0][:ticket_ids]
    assert_equal 2, groups[0][:count]
    assert_equal 64, groups[0][:key].length
  end

  def row(id, extra = {})
    { 'id' => id, 'company_id' => 1, 'title' => 'Voice interrupted', 'incident_id' => nil }.merge(extra)
  end

  def test_recurrence_excludes_missing_classification_and_separates_customers
    rows = [row(1, 'company_id' => nil), row(2, 'company_id' => nil), row(3), row(4, 'company_id' => 2)]
    assert_empty JrcServiceDesk::RecurrenceGrouping.call(rows, recurrence)
  end

  def test_title_normalization_and_unlinked_candidates_preserve_memberships
    rows = [row(1, 'title' => "  VOICE\tinterrupted ", 'incident_id' => 99), row(2), row(3, 'title' => 'Different')]
    group = JrcServiceDesk::RecurrenceGrouping.call(rows, recurrence).first
    assert_equal %w[1 2], group[:ticket_ids]
    assert_equal ['2'], group[:unlinked_ticket_ids]
    assert_equal 'exact_structured_match_human_confirmation_required', group[:method]
    assert_equal 99, rows[0]['incident_id']
  end

  def test_recurrence_group_key_is_stable_and_below_threshold_is_not_a_group
    rows = [row(1), row(2)]
    a = JrcServiceDesk::RecurrenceGrouping.call(rows, recurrence)
    b = JrcServiceDesk::RecurrenceGrouping.call(rows.reverse, recurrence)
    assert_equal a, b
    assert_empty JrcServiceDesk::RecurrenceGrouping.call(rows, recurrence.merge('minimum_occurrences' => 3))
  end

  def test_csv_formula_injection_and_round_trip
    dangerous = ['=1+1', '+SUM(1)', '-1+2', '@SUM(1)', '   =x', "\ttext", "\rtext", "\ntext"]
    dangerous.each { |value| assert_equal "'#{value}", JrcServiceDesk::OperationalCsv.cell(value) }
    assert_equal 'abc', JrcServiceDesk::OperationalCsv.cell("a\u0000bc")
    assert_equal '', JrcServiceDesk::OperationalCsv.cell(nil)
    assert_equal 'normal text', JrcServiceDesk::OperationalCsv.cell('normal text')
    csv = JrcServiceDesk::OperationalCsv.generate(%w[id title], [[1, "Title, with\nquotes \"ok\""], [2, '=CMD()']])
    assert_equal [['id', 'title'], ['1', "Title, with\nquotes \"ok\""], ['2', "'=CMD()"]], CSV.parse(csv)
  end

  def test_canonical_digest_ignores_key_order_not_payload_changes
    a = { 'kind' => 'routing', 'definition' => { 'rules' => [rule] }, 'enabled' => false }
    assert_equal Json.digest(a), Json.digest(a.to_a.reverse.to_h)
    refute_equal Json.digest(a), Json.digest(a.merge('enabled' => true))
    assert_raises(ArgumentError) { Contract.validate!('routing', 'rules' => [rule.merge('output' => { 'queue_id' => Float::INFINITY })]) }
  end
end
