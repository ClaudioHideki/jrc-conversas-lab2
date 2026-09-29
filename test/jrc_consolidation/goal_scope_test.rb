# Executes production GoalProgressService methods against transparent relation
# doubles. Validates predicate construction/intersection and eligible sums.
# It does NOT test generated SQL, indexes, PostgreSQL or ActiveRecord execution.
require 'minitest/autorun'
require 'ostruct'
ROOT = File.expand_path('../..', __dir__) unless defined?(ROOT)
require File.join(ROOT, 'app/services/jrc_crm/commercial_financials')
require File.join(ROOT, 'app/services/jrc_crm/commercial_item_allocation')
require File.join(ROOT, 'app/services/jrc_crm/goal_progress_service')
class Object
  def present?; !nil? && self != false && (!respond_to?(:empty?) || !empty?); end unless method_defined?(:present?)
  def blank?; !present?; end unless method_defined?(:blank?)
end
class QueryDouble
  attr_reader :records, :predicates
  def initialize(records = [], predicates = []); @records, @predicates = records, predicates; end
  def where(filters)
    QueryDouble.new(records.select { |row| filters.all? { |key, value| Array(value).include?(row[key]) } }, predicates + [filters])
  end
  def select(key); records.map { |r| r[key] }; end
  def includes(*); self; end
  def find_each; records.each; end
  def sum(key); records.sum { |row| row[key] }; end
end
class TeamMember
  class << self
    attr_accessor :rows
    def where(filters); QueryDouble.new(rows).where(filters); end
  end
end
class GoalScopeTest < Minitest::Test
  def setup
    @rows = [
      { owner_id: 1, business_unit_id: 10, total_cents: 100 },
      { owner_id: 2, business_unit_id: 10, total_cents: 200 },
      { owner_id: 3, business_unit_id: 20, total_cents: 300 },
      { owner_id: 1, business_unit_id: 20, total_cents: 400 }
    ]
    TeamMember.rows = [{ team_id: 7, user_id: 1 }, { team_id: 7, user_id: 2 }, { team_id: 99, user_id: 3 }]
    @goal = OpenStruct.new(user_id: nil, business_unit_id: nil, team_id: nil, scope_kind: 'company',
      allocations: [], product_id: nil, product_targets: [], account: OpenStruct.new(teams: QueryDouble.new([{ id: 7 }])))
  end
  def scoped(drilldown = nil)
    JrcCrm::GoalProgressService.new(goal: @goal, user_id: drilldown).send(:scoped_responsibility, QueryDouble.new(@rows))
  end
  def test_company_keeps_existing_account_scope
    assert_equal 1000, scoped.sum(:total_cents)
  end
  def test_user_filter
    @goal.user_id = 1
    assert_equal 500, scoped.sum(:total_cents)
  end
  def test_drilldown_intersects_not_replaces_original_user
    @goal.user_id = 1
    assert_equal 0, scoped(2).sum(:total_cents)
  end
  def test_team_and_unit_intersection
    @goal.team_id, @goal.business_unit_id = 7, 10
    assert_equal 300, scoped.sum(:total_cents)
    assert_equal [1, 2], scoped.records.map { |row| row[:owner_id] }
  end
  def test_team_drilldown_outsider_returns_zero
    @goal.team_id = 7
    assert_equal 0, scoped(3).sum(:total_cents)
  end
  def test_team_outside_account_returns_zero
    @goal.team_id = 99
    assert_equal 0, scoped.sum(:total_cents)
  end
  def test_unit_filter
    @goal.business_unit_id = 20
    assert_equal 700, scoped.sum(:total_cents)
  end
  def test_user_allocation_scope
    @goal.scope_kind, @goal.allocations = 'user', [{ 'user_id' => 2 }]
    assert_equal 200, scoped.sum(:total_cents)
    assert_equal 0, scoped(1).sum(:total_cents)
  end
  def test_empty_user_allocations_fail_closed
    @goal.scope_kind = 'user'
    assert_equal 0, scoped.sum(:total_cents)
  end
  def test_product_scope_sums_only_eligible_net_items
    @goal.scope_kind, @goal.product_id = 'product', 11
    order = OpenStruct.new(total_cents: 120_000, monthly_cents: 3000, discount_cents: 10_000,
      order_items: [{ product_id: 11, one_time_cents: 30_000, recurring_cents: 1000, quantity: 1 },
                    { product_id: 22, one_time_cents: 70_000, recurring_cents: 2000, quantity: 2 }])
    service = JrcCrm::GoalProgressService.new(goal: @goal)
    assert_equal 27_000, service.send(:scoped_order_amount, QueryDouble.new([order]), product_id: 11, metric: 'revenue')
    assert_equal 1000, service.send(:scoped_order_amount, QueryDouble.new([order]), product_id: 11, metric: 'mrr')
  end
  def test_product_target_ids_are_combined_without_duplicates
    @goal.scope_kind, @goal.product_targets = 'product', [{ 'product_id' => 11 }, { product_id: 22 }, { product_id: 11 }]
    assert_equal [11, 22], JrcCrm::GoalProgressService.new(goal: @goal).send(:product_filter_ids)
  end
end
