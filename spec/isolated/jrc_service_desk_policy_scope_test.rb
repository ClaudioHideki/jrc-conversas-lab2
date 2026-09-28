# frozen_string_literal: true
# Pure execution of the real TicketPolicy/Scope against explicit in-memory data.
# This does NOT load Rails, SQL, native authentication or OperationalContext.
require 'minitest/autorun'
require 'ostruct'
module JrcServiceDesk
end
require_relative '../../app/services/jrc_service_desk/capabilities'

class ScopeFixtureRelation
  attr_reader :records
  def initialize(records)
    @records = records
  end
  def where(criteria)
    self.class.new(records.select do |row|
      criteria.all? { |key, value| value.is_a?(Array) ? value.include?(row.public_send(key)) : row.public_send(key) == value }
    end)
  end
  def select(field)
    records.map { |row| row.public_send(field) }
  end
  def or(other)
    self.class.new((records + other.records).uniq)
  end
  def exists?(criteria = {})
    !where(criteria).records.empty?
  end
  def none
    self.class.new([])
  end
end

class JrcServiceDesk::BasePolicy
  attr_reader :user_context, :record
  def initialize(context, record)
    @user_context = context
    @record = record
  end
  class Scope
    attr_reader :user_context, :scope
    def initialize(context, scope)
      @user_context = context
      @scope = scope
    end
  end
end
class ScopeFixtureContext
  attr_reader :account
  def initialize(role:, enabled:, grants:, units:, teams: [], memberships: [100])
    @account = OpenStruct.new(id: 1)
    @enabled, @units, @teams, @memberships = enabled, units, teams, memberships
    @capabilities = JrcServiceDesk::Capabilities.new(native_role: role, custom: !grants.nil?, permissions: grants || [])
  end
  def capability?(key)
    @enabled && @capabilities.allowed?(key)
  end
  def native_operator?
    capability?(:module_view)
  end
  def unit_scope
    ScopeFixtureRelation.new(@units.map { |id| OpenStruct.new(id: id) })
  end
  def active_memberships
    ScopeFixtureRelation.new(@memberships.map { |id| OpenStruct.new(id: id) })
  end
  def native_team_ids
    @teams
  end
  def record_in_account?(record)
    record.account_id == account.id
  end
end
class JrcServiceDesk::OperationalContext
  def self.new(context)
    context.fetch(:fixture)
  end
end
class JrcServiceDesk::Ticket
  class << self
    attr_accessor :fixture_relation
    def where(criteria)
      fixture_relation.where(criteria)
    end
    def none
      fixture_relation.none
    end
  end
end
require_relative '../../app/policies/jrc_service_desk/operational_policy'
require_relative '../../app/policies/jrc_service_desk/ticket_policy'

class ServiceDeskPolicyScopeTest < Minitest::Test
  def setup
    @records = [
      { id: 1, account_id: 1, unit_id: 10, created_by_membership_id: 100, assignee_membership_id: nil, team_id: nil },
      { id: 2, account_id: 1, unit_id: 11, created_by_membership_id: 200, assignee_membership_id: nil, team_id: 90 },
      { id: 3, account_id: 2, unit_id: 20, created_by_membership_id: 300, assignee_membership_id: nil, team_id: 90 },
      { id: 4, account_id: 1, unit_id: 10, created_by_membership_id: 400, assignee_membership_id: nil, team_id: nil },
      { id: 5, account_id: 1, unit_id: 10, created_by_membership_id: 500, assignee_membership_id: nil, team_id: 90 }
    ].map { |values| OpenStruct.new(values.merge(persisted?: true)) }
    JrcServiceDesk::Ticket.fixture_relation = ScopeFixtureRelation.new(@records)
  end
  def context(role: 'agent', enabled: true, grants: nil, units: [10], teams: [])
    { fixture: ScopeFixtureContext.new(role: role, enabled: enabled, grants: grants, units: units, teams: teams) }
  end
  def ids(ctx)
    JrcServiceDesk::TicketPolicy::Scope.new(ctx, JrcServiceDesk::Ticket).resolve.select(:id)
  end
  def grants(*keys)
    keys.map { |key| "jrc_service_desk_#{key}" }
  end
  def test_real_scope_ownership_and_native_profile_preserve_account_and_unit
    assert_equal [1], ids(context)
    assert_equal [1, 4, 5], ids(context(role: 'administrator'))
    assert_equal [1, 5], ids(context(teams: [90]))
    assert_equal [], ids(context(role: 'administrator', units: []))
    assert_equal [], ids(context(role: 'administrator', enabled: false))
  end
  def test_team_never_crosses_an_ungranted_unit_or_account
    result = ids(context(teams: [90]))
    refute_includes result, 2
    refute_includes result, 3
    assert_includes result, 5
  end
  def test_custom_read_all_never_extends_unit_or_account
    values = grants('module_view', 'tickets_view', 'tickets_view_all')
    assert_equal [1, 4, 5], ids(context(grants: values))
    assert_equal [], ids(context(grants: values, units: []))
  end
  def test_admin_bit_is_not_fallback_for_custom_role_with_no_action
    values = grants('module_view')
    assert_equal [], ids(context(role: 'administrator', grants: values))
    assert_equal false, JrcServiceDesk::TicketPolicy.new(context(role: 'administrator', grants: values), @records[0]).update?
  end
  def test_cartesian_product_feature_membership_capability_and_scope
    [false, true].repeated_permutation(3).each do |flag, membership, capability|
      values = grants('module_view', 'tickets_view') + (capability ? grants('tickets_edit') : [])
      ctx = context(role: 'administrator', enabled: flag, units: membership ? [10] : [], grants: values)
      @records.each do |row|
        expected = flag && membership && capability && row.id == 1
        assert_equal expected, JrcServiceDesk::TicketPolicy.new(ctx, row).update?, [flag, membership, capability, row.id].inspect
      end
    end
  end
  def test_distinct_assignment_transfer_priority_history_notes_sla
    action_keys = { assign: 'tickets_assign', transfer: 'tickets_transfer', change_priority: 'priority_change', view_history: 'history_view', view_notes: 'notes_view', view_sla: 'sla_view' }
    action_keys.each do |action, key|
      ctx = context(grants: grants('module_view', 'tickets_view', key))
      action_keys.each_key do |other|
        assert_equal action == other, JrcServiceDesk::TicketPolicy.new(ctx, @records[0]).public_send("#{other}?")
      end
    end
  end
end
