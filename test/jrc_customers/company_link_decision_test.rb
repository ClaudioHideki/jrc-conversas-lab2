# No Rails/DB: validates the exact-ID decision rule used by writes and backfills.
require 'minitest/autorun'
module JrcCustomers; end
require_relative '../../app/services/jrc_customers/company_link_decision'
class CustomerCompanyLinkDecisionTest < Minitest::Test
  Decision = JrcCustomers::CompanyLinkDecision
  def test_no_company_is_valid_for_internal_projects
    assert_nil Decision.resolve
    assert_nil Decision.resolve(candidates: [nil, ''])
  end
  def test_unique_existing_id_is_inferred
    assert_equal 42, Decision.resolve(candidates: [42, '42', nil])
  end
  def test_explicit_matching_choice_is_preserved
    assert_equal 42, Decision.resolve(explicit: '42', candidates: [42])
  end
  def test_explicit_company_without_contact_is_allowed
    assert_equal 42, Decision.resolve(explicit: 42)
  end
  def test_different_contacts_or_origins_require_review
    assert_raises(Decision::Conflict) { Decision.resolve(candidates: [42, 51]) }
  end
  def test_explicit_selection_does_not_override_a_different_origin
    assert_raises(Decision::Conflict) { Decision.resolve(explicit: 42, candidates: [51]) }
  end
  def test_names_and_operator_labels_are_not_identity_evidence
    ['HOYA Lens Brasil', 'Operator', '42x'].each do |label|
      assert_raises(Decision::Conflict) { Decision.resolve(candidates: [label]) }
    end
  end
  def test_rejects_noncanonical_identifiers
    [0, -1, 1.5, false, {}, [], '01', '+1', ' 1', '1e2', '0', '9223372036854775808'].each do |value|
      assert_raises(Decision::Conflict) { Decision.resolve(explicit: value) }
    end
  end
  def test_input_order_does_not_change_identity
    [42, '42', nil].permutation.each { |values| assert_equal 42, Decision.resolve(candidates: values) }
  end
  def test_native_bigint_does_not_round
    assert_equal 9223372036854775807, Decision.resolve(explicit: '9223372036854775807')
  end
end
