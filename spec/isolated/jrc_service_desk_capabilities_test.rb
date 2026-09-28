# frozen_string_literal: true
# Pure native-role interpretation tests. No Rails, database or authentication is exercised.
require 'minitest/autorun'
module JrcServiceDesk; end
require_relative '../../app/services/jrc_service_desk/capabilities'

class ServiceDeskCapabilitiesTest < Minitest::Test
  C = JrcServiceDesk::Capabilities
  def custom(*keys)
    C.new(custom: true, native_role: 'administrator', permissions: keys.flatten.map { |key| "#{C::PREFIX}#{key}" })
  end

  def test_unknown_and_empty_roles_deny_every_action
    [nil, '', 'super_admin', 'administrator ', 'custom_role'].each do |role|
      assert_empty C.new(native_role: role).effective
    end
  end

  def test_native_admin_has_explicit_catalog_not_wildcards
    admin = C.new(native_role: 'administrator')
    assert_equal 33, admin.effective.length
    %w[module_view tickets_view tickets_view_all settings_view lifecycle_policies_manage].each { |key| assert admin.allowed?(key) }
    %w[unit_membership_manage system_admin financial_manage projects_view unknown].each { |key| refute admin.allowed?(key) }
  end

  def test_standard_agent_does_not_inherit_sensitive_configuration
    agent = C.new(native_role: 'agent')
    %w[module_view tickets_view tickets_create tickets_edit tickets_assign tickets_transfer priority_change
       notes_view notes_add history_view conversations_view conversations_link sla_view dashboard_view].each { |key| assert agent.allowed?(key), key }
    %w[tickets_view_all settings_view lifecycle_policies_manage services_manage queues_manage categories_manage
       priorities_manage statuses_manage contract_conditions_view sla_snapshots_record].each { |key| refute agent.allowed?(key), key }
  end

  def test_custom_role_replaces_admin_defaults
    role = custom('module_view', 'tickets_view')
    assert_equal %w[module_view tickets_view], role.effective
    %w[tickets_edit resolve tickets_view_all dashboard_view].each { |key| refute role.allowed?(key) }
  end

  def test_membership_or_legacy_permissions_are_not_capabilities
    role = C.new(custom: true, permissions: %w[administrator agent custom_role conversation_manage contact_manage report_manage])
    assert_empty role.effective
    refute custom('tickets_view').allowed?(:tickets_view)
    refute custom('tickets_edit').allowed?(:tickets_edit)
  end

  def test_action_grants_are_independent
    role = custom('module_view', 'tickets_view', 'tickets_assign')
    assert role.allowed?(:tickets_assign)
    refute role.allowed?(:tickets_transfer)
    refute role.allowed?(:priority_change)
    refute role.allowed?(:tickets_edit)
    role = custom('module_view', 'tickets_view', 'priority_change')
    assert role.allowed?(:priority_change)
    refute role.allowed?(:tickets_edit)
  end

  def test_lifecycle_requires_specific_action_and_readback_capabilities
    %w[pause resume resolve close cancel reopen work_status_change].each do |action|
      base = %w[module_view tickets_view history_view sla_view]
      refute custom(*base).allowed?(action)
      assert custom(*base, action).allowed?(action)
      base.each { |missing| refute custom(*(base - [missing]), action).allowed?(action), "#{action}/#{missing}" }
    end
  end

  def test_each_dependency_is_required_without_silent_auto_grants
    C::DEPENDENCIES.each do |key, dependencies|
      dependencies.each do |missing|
        refute custom(*(C::KEYS - [missing])).allowed?(key), "#{key} needs #{missing}"
      end
    end
  end

  def test_configuration_requires_named_capability_not_settings_alone
    base = %w[module_view settings_view lookups_view]
    %w[queues_manage categories_manage priorities_manage statuses_manage services_manage lifecycle_policies_manage].each do |key|
      refute custom(*base).allowed?(key)
      assert custom(*base, key).allowed?(key)
    end
  end

  def test_permissions_input_is_filtered_and_never_mutated
    values = ['jrc_service_desk_module_view', {}, nil, :jrc_service_desk_tickets_view, 'JRC_SERVICE_DESK_TICKETS_VIEW']
    before = Marshal.dump(values)
    assert_equal ['module_view'], C.new(custom: true, permissions: values).effective
    assert_equal before, Marshal.dump(values)
  end

  def test_no_cyclic_dependencies_or_unknown_catalog_entries
    visit = lambda do |key, path|
      refute_includes path, key
      assert_includes C::KEYS, key
      C::DEPENDENCIES.fetch(key, []).each { |child| visit.call(child, path + [key]) }
    end
    C::KEYS.each { |key| visit.call(key, []) }
    assert_equal C::KEYS.length, C::KEYS.uniq.length
    assert_equal C::PERMISSIONS.length, C::PERMISSIONS.uniq.length
  end
end
