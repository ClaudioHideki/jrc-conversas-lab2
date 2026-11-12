require 'minitest/autorun'
require 'date'
module JrcBackoffice
  class Documents
    class Conflict < StandardError; end
  end
end
require_relative '../../app/services/jrc_backoffice/document_validity'

class DocumentValidityTest < Minitest::Test
  Service = JrcBackoffice::DocumentValidity

  def test_unknown_validity_is_not_invented
    assert_nil Service.parse(nil)
    assert_equal 'approved', Service.status(decision_status: 'approved', expires_on: nil, local_date: Date.new(2026, 11, 9))
  end

  def test_strict_calendar_date
    assert_equal Date.new(2028, 2, 29), Service.parse('2028-02-29')
    assert_equal Date.new(2026, 11, 9), Service.parse(Date.new(2026, 11, 9))
  end

  [false, true, 123, [], {}, '', '09/11/2026', '2026-11-9', '2026-02-29', '2026-11-09T00:00:00Z',
   ' 2026-11-09', '2026-13-01', '0000-01-01', '10000-01-01', Date.new(10000, 1, 1)].each_with_index do |value, index|
    define_method("test_rejects_invalid_calendar_#{index}") { assert_raises(ArgumentError) { Service.parse(value) } }
  end

  def test_date_remains_valid_until_end_of_its_recorded_local_day
    assert_equal 'approved', Service.status(decision_status: 'approved', expires_on: '2026-11-09', local_date: Date.new(2026, 11, 9))
    assert_equal 'expired', Service.status(decision_status: 'approved', expires_on: '2026-11-09', local_date: Date.new(2026, 11, 10))
  end

  def test_expiration_never_turns_rejection_into_approval
    %w[rejected expired review_required processing].each do |state|
      assert_equal state, Service.status(decision_status: state, expires_on: '2026-11-10', local_date: Date.new(2026, 11, 9))
    end
  end

  def test_omitted_value_preserves_previous_expiration
    old = Date.new(2026, 12, 1)
    assert_equal old, Service.resolve(value: Service::UNSPECIFIED, previous: old)
  end

  def test_explicit_clear_is_distinct_from_omission
    assert_nil Service.resolve(value: nil, previous: Date.new(2026, 12, 1))
  end

  def test_no_implicit_system_timezone
    assert_raises(ArgumentError) { Service.status(decision_status: 'approved', expires_on: '2026-11-09', local_date: Time.now) }
  end

  def test_first_decision_and_exact_revision
    assert_nil Service.revision!(nil, nil)
    assert_nil Service.revision!(42, 42)
    assert_nil Service.revision!(Service::UNSPECIFIED, 42)
  end

  def test_stale_revision_is_not_reused
    assert_raises(JrcBackoffice::Documents::Conflict) { Service.revision!(nil, 42) }
    assert_raises(JrcBackoffice::Documents::Conflict) { Service.revision!(41, 42) }
    assert_raises(JrcBackoffice::Documents::Conflict) { Service.revision!(42, nil) }
  end

  [false, true, '42', 0, -1, 1.5, [], {}].each_with_index do |value, index|
    define_method("test_rejects_revision_type_#{index}") { assert_raises(ArgumentError) { Service.revision!(value, 42) } }
  end
  def test_new_expiration_requires_an_explicit_revision
    assert_raises(ArgumentError) { JrcBackoffice::DocumentValidity.revision!(JrcBackoffice::DocumentValidity::UNSPECIFIED, nil, validity: '2099-01-01') }
  end

  def test_clearing_expiration_requires_an_explicit_revision
    assert_raises(ArgumentError) { JrcBackoffice::DocumentValidity.revision!(JrcBackoffice::DocumentValidity::UNSPECIFIED, 1, validity: nil) }
  end

  def test_explicit_first_decision_with_date_has_no_previous_revision
    assert_nil JrcBackoffice::DocumentValidity.revision!(nil, nil, validity: '2099-01-01')
  end

end
