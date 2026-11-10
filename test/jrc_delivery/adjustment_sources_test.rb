require 'minitest/autorun'
module JrcApprovals
  class Error < StandardError; end
  class TierRanges
    MAX_EXACT_BOUND = 9_007_199_254_740_991
  end
end
require_relative '../../app/services/jrc_approvals/adjustment_sources'

class AdjustmentSourcesTest < Minitest::Test
  Source = JrcApprovals::AdjustmentSources

  Source::SOURCES.each do |key, type|
    define_method("test_installed_#{key.tr('.', '_')}") { assert_equal type, Source.type!(key: key, resource_type: type) }
  end

  %w[crm.deal_price backoffice.release contracts.company_signature service_desk.ticket_update __send__ Object].each do |key|
    define_method("test_denies_uninstalled_#{key.tr('.', '_')}") do
      assert_raises(JrcApprovals::Error) { Source.type!(key: key, resource_type: 'JrcCrm::SalesOrder') }
    end
  end

  def test_resource_type_must_match_the_installed_origin
    assert_raises(JrcApprovals::Error) { Source.type!(key: 'crm.order_price', resource_type: 'JrcCrm::Proposal') }
    assert_raises(JrcApprovals::Error) { Source.type!(key: 'crm.proposal_send', resource_type: 'JrcCrm::SalesOrder') }
  end

  %w[draft pending].each do |status|
    define_method("test_uncommitted_#{status}") { assert Source.order_mutable?(status: status, terms_locked: false, invoiced: false) }
  end

  %w[approved separating invoiced shipped completed canceled unknown].each do |status|
    define_method("test_blocks_operational_#{status}") { refute Source.order_mutable?(status: status, terms_locked: false, invoiced: false) }
  end

  def test_accepted_terms_and_invoice_are_hard_boundaries
    refute Source.order_mutable?(status: 'pending', terms_locked: true, invoiced: false)
    refute Source.order_mutable?(status: 'pending', terms_locked: false, invoiced: true)
    refute Source.order_mutable?(status: 'pending', terms_locked: nil, invoiced: false)
  end

  [false, true, '100', 1.1, -1, nil, [], {}, Float::INFINITY, JrcApprovals::TierRanges::MAX_EXACT_BOUND + 1].each_with_index do |value, i|
    define_method("test_rejects_invalid_discount_#{i}") { assert_raises(JrcApprovals::Error) { Source.discount!('discount_cents' => value) } }
  end

  def test_bounded_integer_money
    assert_equal 0, Source.discount!('discount_cents' => 0)
    assert_equal 12345, Source.discount!('discount_cents' => 12345)
  end

  def test_extra_fields_cannot_edit_status_customer_or_price
    %w[status total_cents contact_id owner_id snapshot].each do |field|
      assert_raises(JrcApprovals::Error) { Source.discount!('discount_cents' => 100, field => 1) }
    end
  end
end
