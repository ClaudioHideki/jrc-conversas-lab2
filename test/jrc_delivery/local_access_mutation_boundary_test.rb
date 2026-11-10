require 'minitest/autorun'
require 'ostruct'
require 'json'
module JrcRelationship; end
require_relative '../../app/services/jrc_relationship/local_role_rules'
require_relative '../../app/services/jrc_relationship/local_access'
# Real mutation boundary, database relations doubled explicitly.
class RelationForLocalBoundary
  def initialize(values) = @values = values
  def select(*) = self
  def pluck(*) = @values
end
class JrcRelationship::PortfolioGroupAssignment
  def self.where(**) = RelationForLocalBoundary.new([3])
end
class JrcRelationship::PortfolioGroup
  def self.where(**) = RelationForLocalBoundary.new([3])
end
class JrcRelationship::Configuration
  class << self
    attr_accessor :stored
    def where(**) = RelationForLocalBoundary.new(stored)
  end
end
class Team
  def self.where(**) = RelationForLocalBoundary.new([5])
end
class TeamMember
  def self.where(**) = RelationForLocalBoundary.new([5])
end
class LocalAccessMutationBoundaryTest < Minitest::Test
  def setup
    @member = OpenStruct.new(account_id: 1, user_id: 8)
    @assignment = OpenStruct.new(account_id: 1, owner_id: 8, team_id: 5, id: 11)
    JrcRelationship::Configuration.stored = []
  end
  def allowed(action = 'work')
    JrcRelationship::LocalAccess.assignment_allowed?(@member, @assignment, action)
  end
  def rule
    {'enabled' => true, 'roles' => JSON.parse(JSON.generate(JrcRelationship::LocalRoleRules::DEFAULTS)),
     'members' => [{'user_id' => 8, 'role' => 'analyst', 'grants' => [], 'document_categories' => []}]}
  end
  def test_boolean_false_is_not_a_missing_policy_during_mutation
    JrcRelationship::Configuration.stored = [{'portfolio_local_access' => false}]
    assert_raises(ArgumentError) { allowed }
  end
  def test_malformed_portfolio_cannot_be_ignored_beside_valid_account_policy
    JrcRelationship::Configuration.stored = [{'portfolio_local_access' => rule}, {'portfolio_local_access' => false}]
    assert_raises(ArgumentError) { allowed }
  end
  [true, [], 'invalid', {'enabled' => 'false'}, {'enabled' => true}].each_with_index do |value, index|
    define_method("test_other_malformed_policy_#{index}_is_rejected") do
      JrcRelationship::Configuration.stored = [{'portfolio_local_access' => value}]
      assert_raises(ArgumentError) { allowed }
    end
  end
  def test_absent_and_null_preserve_native_authority_boundary
    JrcRelationship::Configuration.stored = [{}, {'portfolio_local_access' => nil}]
    assert allowed
  end
  def test_valid_disabled_policy_preserves_native_authority_boundary
    JrcRelationship::Configuration.stored = [{'portfolio_local_access' => rule.merge('enabled' => false)}]
    assert allowed
  end
  def test_valid_analyst_does_not_get_execution_power
    JrcRelationship::Configuration.stored = [{'portfolio_local_access' => rule}]
    assert allowed
    refute allowed('execute_transfer')
  end
  def test_wrong_account_stays_denied
    @assignment.account_id = 2
    refute allowed
  end
  def test_own_scope_stays_restrictive
    @assignment.owner_id = 9
    JrcRelationship::Configuration.stored = [{'portfolio_local_access' => rule}]
    refute allowed
  end
  def test_independent_document_grant_is_not_created
    JrcRelationship::Configuration.stored = [{'portfolio_local_access' => rule}]
    refute allowed('document_download')
  end
end
