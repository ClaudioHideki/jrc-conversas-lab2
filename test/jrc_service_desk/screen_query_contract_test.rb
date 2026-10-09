# frozen_string_literal: true

require 'minitest/autorun'
module JrcServiceDesk; end
require_relative '../../app/services/jrc_service_desk/input'
require_relative '../../app/services/jrc_service_desk/query_parameters'

class ServiceDeskScreenQueryContractTest < Minitest::Test
  def test_phase_selectors_are_explicit
    %w[active open waiting resolved closed cancelled].each do |phase|
      assert_equal phase, JrcServiceDesk::QueryParameters.new({ phase: phase })['phase']
    end
  end

  def test_unassigned_is_a_filter_not_a_permission
    filters = JrcServiceDesk::QueryParameters.new({ assignment: 'unassigned', operator_company_id: '3', unit_id: '10' })
    assert_equal 'unassigned', filters['assignment']
    assert_equal 3, filters['operator_company_id']
    assert_equal 10, filters['unit_id']
  end

  def test_unknown_or_conflicting_filters_are_rejected
    [{ phase: 'all' }, { phase: ['open'] }, { assignment: 'assigned' },
     { assignment: 'unassigned', mine: 'true' }, { permissions: 'all' }].each do |filters|
      assert_raises(ArgumentError) { JrcServiceDesk::QueryParameters.new(filters) }
    end
  end

  def test_existing_query_defaults_and_protocol_remain_unchanged
    filters = JrcServiceDesk::QueryParameters.new({ q: '#249', mine: 'true' })
    assert_equal '#249', filters['q']
    assert_equal 'true', filters['mine']
    assert_equal 1, filters.page
    assert_equal 20, filters.per_page
  end

  def test_catalogues_do_not_inherit_operational_only_filters
    assert_raises(ArgumentError) { JrcServiceDesk::QueryParameters.new({ phase: 'open' }, catalog: true) }
    assert_raises(ArgumentError) { JrcServiceDesk::QueryParameters.new({ assignment: 'unassigned' }, catalog: true) }
  end
end
