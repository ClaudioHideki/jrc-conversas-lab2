require 'minitest/autorun'
require 'json'
require 'ostruct'
module JrcRelationship; end
require_relative '../app/services/jrc_relationship/local_role_rules'
require_relative '../app/services/jrc_relationship/local_access'
require_relative '../app/services/jrc_relationship/document_access'

# Real rule/scope entry points; database lookup only is a small test double.
# This is NOT a Rails/PostgreSQL integration test.
class JrcRelationship::Configuration
  class << self
    attr_accessor :test_rules
    def where(*)
      self
    end
    def each(&block)
      test_rules.each(&block)
    end
    def to_a
      test_rules
    end
  end
end

class LocalRoleBoundariesTest < Minitest::Test
  R = JrcRelationship::LocalRoleRules
  def configuration(role = 'viewer')
    { 'enabled' => true, 'roles' => JSON.parse(JSON.generate(R::DEFAULTS)),
      'members' => [{ 'user_id' => 8, 'role' => role, 'grants' => [], 'document_categories' => [] }] }
  end

  %w[work team configure manage_portfolios request_transfer approve_transfer execute_transfer request_eligibility manage_eligibility document_upload document_replace document_manage].each do |action|
    define_method("test_consulta_cannot_be_reconfigured_for_#{action}") do
      value = configuration
      value['roles']['viewer']['actions'] << action
      assert_raises(ArgumentError) { R.normalize!(value) }
    end
  end

  %w[configure manage_portfolios approve_transfer execute_transfer request_eligibility manage_eligibility document_manage document_restricted].each do |action|
    define_method("test_analyst_cannot_be_reconfigured_for_#{action}") do
      value = configuration('analyst')
      value['roles']['analyst']['actions'] << action
      assert_raises(ArgumentError) { R.normalize!(value) }
    end
  end

  %w[configure manage_portfolios execute_transfer manage_eligibility document_manage document_upload document_replace].each do |action|
    define_method("test_supervisor_cannot_be_reconfigured_for_#{action}") do
      value = configuration('supervisor')
      value['roles']['supervisor']['actions'] << action
      assert_raises(ArgumentError) { R.normalize!(value) }
    end
  end

  def test_consulta_explicit_read_only_exports_remain_configurable
    value = configuration
    value['roles']['viewer']['actions'] += %w[export_data document_view document_download]
    value['members'].first['grants'] = %w[export_data document_view document_download]
    value['members'].first['document_categories'] = ['registration']
    assert R.allowed?(value, user_id: 8, action: 'export_data', owner_id: 8)
    assert R.allowed?(value, user_id: 8, action: 'document_download', owner_id: 8, document_category: 'registration')
  end

  def test_read_only_actions_need_separate_grants_even_when_configured
    value = configuration
    value['roles']['viewer']['actions'] += %w[export_data document_view document_download]
    refute R.allowed?(value, user_id: 8, action: 'export_data', owner_id: 8)
    refute R.allowed?(value, user_id: 8, action: 'document_download', owner_id: 8, document_category: 'registration')
  end

  def test_supervisor_can_request_but_not_apply_eligibility
    value = configuration('supervisor')
    assert R.allowed?(value, user_id: 8, action: 'request_eligibility', owner_id: 8)
    refute R.allowed?(value, user_id: 8, action: 'manage_eligibility', owner_id: 8)
  end

  def test_manager_capabilities_are_still_configurable_not_granted
    value = configuration('manager')
    assert R.allowed?(value, user_id: 8, action: 'configure', owner_id: 8)
    value['roles']['manager']['actions'].delete('configure')
    refute R.allowed?(value, user_id: 8, action: 'configure', owner_id: 8)
  end

  def test_disabled_invalid_configuration_does_not_escape_validation
    value = configuration
    value['roles']['viewer']['actions'] << 'work'
    value['enabled'] = false
    assert_raises(ArgumentError) { R.normalize!(value) }
  end

  [false, [], 'invalid', {'enabled' => 'true'}, {'enabled' => true}].each_with_index do |invalid, index|
    define_method("test_assignment_scope_denies_malformed_saved_rule_#{index}") do
      JrcRelationship::Configuration.test_rules = [OpenStruct.new(scope_key: 'account', rules: {'portfolio_local_access' => invalid})]
      member = OpenStruct.new(account_id: 1, user_id: 8)
      assert_raises(ArgumentError) { JrcRelationship::LocalAccess.scope_assignments({account_user: member}, Object.new) }
    end
    define_method("test_document_scope_denies_malformed_saved_rule_#{index}") do
      JrcRelationship::Configuration.test_rules = [OpenStruct.new(scope_key: 'account', rules: {'portfolio_local_access' => invalid})]
      context = OpenStruct.new(account: OpenStruct.new(id: 1), policy: OpenStruct.new(documents_manage?: true, documents_restricted?: true))
      assert_raises(ArgumentError) { JrcRelationship::DocumentAccess.scope(context, Object.new) }
    end
  end
end
