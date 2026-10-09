# frozen_string_literal: true

require 'minitest/autorun'
module JrcServiceDesk; end
require_relative '../../app/services/jrc_service_desk/ticket_search'

class TicketNumberContractTest < Minitest::Test
  def test_official_number_accepts_plain_or_hash_prefix
    assert_equal 249, JrcServiceDesk::TicketSearch.identifier('249')
    assert_equal 249, JrcServiceDesk::TicketSearch.identifier('#249')
    assert_equal 249, JrcServiceDesk::TicketSearch.identifier('  #249  ')
  end

  def test_postgresql_identifier_bounds_preserve_full_precision
    assert_equal 9_223_372_036_854_775_807, JrcServiceDesk::TicketSearch.identifier('#9223372036854775807')
    assert_nil JrcServiceDesk::TicketSearch.identifier('9223372036854775808')
    assert_equal 9_007_199_254_740_993, JrcServiceDesk::TicketSearch.identifier('9007199254740993')
  end

  def test_invalid_numbers_do_not_become_identifiers
    ['', '0', '#0', '0249', '#0249', '-1', '1.5', '1e3', 'SD-000249', '##249', '1 OR 1=1', '9' * 30, nil].each do |query|
      assert_nil JrcServiceDesk::TicketSearch.identifier(query), query.inspect
    end
  end
end
