# frozen_string_literal: true
require 'minitest/autorun'
require 'json'
module JrcServiceDesk; end
require_relative '../../app/services/jrc_service_desk/input'
require_relative '../../app/services/jrc_service_desk/configuration_contract'

class ServiceDeskConfigurationContractTest < Minitest::Test
  C = JrcServiceDesk::ConfigurationContract
  def test_all_supported_create_contracts_are_explicit
    C::FIELDS.each do |resource, fields|
      data = { 'name' => 'Local test', 'code' => 'unique', 'active' => false }
      data['position'] = 0 if fields.include?('position')
      data.merge!('phase' => 'open', 'initial' => false) if fields.include?('phase')
      assert_equal data, C.attributes(resource, data, create: true)
      data.keys.each { |key| assert_raises(ArgumentError) { C.attributes(resource, data.reject { |k, _v| k == key }, create: true) } }
    end
  end
  def test_client_identifiers_do_not_establish_account_or_unit
    %w[account_id unit_id operator_company_id actor_id role permissions class table created_at lock_version].each do |field|
      assert_raises(ArgumentError) { C.attributes('categories', { 'name' => 'x', field => '1' }, create: false) }
    end
  end
  def test_catalogue_names_are_a_closed_set
    %w[units operator_companies memberships users tickets policies ActiveRecord::Base ../queues].each do |resource|
      assert_raises(KeyError) { C.attributes(resource, { 'name' => 'x' }, create: false) }
    end
  end
  def test_code_is_immutable_on_update
    assert_raises(ArgumentError) { C.attributes('categories', { 'code' => 'new' }, create: false) }
  end
  def test_explicit_booleans_not_strings_or_truthiness
    [nil, 'true', 'false', 1, 0, [], {}].each do |value|
      assert_raises(ArgumentError) { C.attributes('categories', { 'active' => value }, create: false) }
    end
    [false, true].each { |value| assert_equal({ 'active' => value }, C.attributes('services', { 'active' => value }, create: false)) }
  end
  def test_position_bounds_and_types
    [-1, 2_147_483_648, 0.5, '1', nil].each { |v| assert_raises(ArgumentError) { C.attributes('priorities', { 'position' => v }, create: false) } }
    [0, 2_147_483_647].each { |v| assert_equal v, C.attributes('priorities', { 'position' => v }, create: false)['position'] }
  end
  def test_team_ids_strict_or_null
    assert_nil C.attributes('queues', { 'team_id' => nil }, create: false)['team_id']
    ['1', 2].each { |v| assert_equal v.to_i, C.attributes('queues', { 'team_id' => v }, create: false)['team_id'] }
    ['01', '-1', '1;drop', [], {}, true, 0].each { |v| assert_raises(ArgumentError) { C.attributes('queues', { 'team_id' => v }, create: false) } }
  end
  def test_text_limits_and_empty_rejected
    ['', ' ', "\n", nil, 1, true, 'x' * 256].each { |v| assert_raises(ArgumentError) { C.attributes('categories', { 'name' => v }, create: false) } }
    assert_equal 'x' * 255, C.attributes('categories', { 'name' => 'x' * 255 }, create: false)['name']
  end
  def test_phases_known_only
    C::PHASES.each { |v| assert_equal v, C.attributes('statuses', { 'phase' => v }, create: false)['phase'] }
    ['unknown', 'OPEN', '', nil, 1].each { |v| assert_raises(ArgumentError) { C.attributes('statuses', { 'phase' => v }, create: false) } }
  end
  def test_revision_required_canonical
    assert_equal 'a' * 64, C.revision('a' * 64)
    [nil, '', 'a' * 63, 'g' * 64, 'A' * 64, []].each { |v| assert_raises(ArgumentError) { C.revision(v) } }
  end
end
