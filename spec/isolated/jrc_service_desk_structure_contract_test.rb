# frozen_string_literal: true
# Pure contract/designation/capability tests. NO Rails/SQL/native authentication.
require 'minitest/autorun'
module JrcServiceDesk; end
require_relative '../../app/services/jrc_service_desk/input'
require_relative '../../app/services/jrc_service_desk/structure_contract'
require_relative '../../app/services/jrc_service_desk/initializer_authority'
require_relative '../../app/services/jrc_service_desk/capabilities'

class ServiceDeskStructureContractTest < Minitest::Test
  C = JrcServiceDesk::StructureContract
  A = JrcServiceDesk::InitializerAuthority

  def fields(resource)
    case resource
    when 'operator_companies' then { 'name' => 'Test operator', 'code' => 'test', 'active' => true }
    when 'units' then { 'name' => 'Test unit', 'code' => 'test', 'active' => true, 'operator_company_id' => 5 }
    else { 'unit_id' => 10, 'account_user_id' => 20, 'active' => true }
    end
  end

  def test_no_initializer_is_preconfigured
    assert_equal [], A.ids('')
    assert_equal [], A.ids('  ')
    [nil, [], {}, 2, '0', '-1', '2,', '2,abc', '2;3', '1e3', '01', '9223372036854775808'].each { |v| assert_equal [], A.ids(v), v.inspect }
    assert_equal [2, 3], A.ids('2, 3,2')
  end

  def test_native_administrator_receives_structure_without_elevating_other_roles
    %w[agent super_admin].each do |role|
      caps = JrcServiceDesk::Capabilities.new(native_role: role)
      %w[structure_view operator_companies_manage units_manage unit_memberships_manage].each { |key| refute caps.allowed?(key) }
    end
    admin = JrcServiceDesk::Capabilities.new(native_role: 'administrator')
    %w[structure_view operator_companies_manage units_manage unit_memberships_manage].each { |key| assert admin.allowed?(key) }
    assert_equal 37, admin.effective.size
    assert_equal 23, JrcServiceDesk::Capabilities.new(native_role: 'agent').effective.size
  end

  def test_explicit_structure_role_does_not_enable_operations
    caps = JrcServiceDesk::Capabilities.new(custom: true, native_role: 'administrator', permissions:
      %w[structure_view operator_companies_manage units_manage unit_memberships_manage].map { |v| "jrc_service_desk_#{v}" })
    assert caps.allowed?(:units_manage)
    %w[module_view tickets_view tickets_create tickets_view_all resolve dashboard_view].each { |key| refute caps.allowed?(key) }
    refute JrcServiceDesk::Capabilities.new(custom: true, permissions: ['jrc_service_desk_units_manage']).allowed?(:units_manage)
  end

  C::RESOURCES.each do |resource|
    define_method("test_#{resource}_explicit_attributes_and_ids") do
      assert_equal fields(resource), C.attributes(resource, fields(resource), create: true)
      fields(resource).each_key { |key| assert_raises(ArgumentError) { C.attributes(resource, fields(resource).reject { |k,_| k == key }, create: true) } }
      %w[account_id id user_id role roles permissions authority super_admin company_id type].each do |key|
        assert_raises(ArgumentError) { C.attributes(resource, fields(resource).merge(key => 1), create: true) }
      end
      [nil, 0, 1, 'true', 'false', []].each { |v| assert_raises(ArgumentError) { C.attributes(resource, fields(resource).merge('active' => v), create: true) } }
    end
    define_method("test_#{resource}_ownership_immutable") do
      assert_equal({ 'active' => false }, C.attributes(resource, { 'active' => false }, create: false))
      %w[account_id code operator_company_id unit_id account_user_id].each do |key|
        assert_raises(ArgumentError) { C.attributes(resource, { key => 5 }, create: false) }
      end
      assert_raises(ArgumentError) { C.attributes(resource, {}, create: false) }
    end
  end

  def test_human_confirmation_and_reason_cannot_be_inferred
    [nil, false, 1, 'true', '', {}, []].each { |v| assert_raises(ArgumentError) { C.confirmation(v) } }
    assert C.confirmation(true)
    assert C.confirmation('confirmed')
    assert_equal 'CHG-42', C.reason(' CHG-42 ')
    [nil, 3, 'a', 'x' * 501, "abc\0def"].each { |v| assert_raises(ArgumentError) { C.reason(v) } }
  end

  def test_revision_and_resource_closed
    assert_equal 'a' * 64, C.revision('a' * 64)
    [nil, 1, 'A' * 64, '', 'a' * 63].each { |v| assert_raises(ArgumentError) { C.revision(v) } }
    %w[tickets companies users roles UnitMembership].each { |r| assert_raises(KeyError) { C.attributes(r, {}, create: true) } }
  end
end
