# Isolated declaration recording only. No SQL/ActiveRecord implementation is executed.
require 'json'
require 'minitest/autorun'
# Recorder-only stand-in for the existing migration's ActiveSupport whitespace helper.
class String
  def squish; split.join(' '); end
end
module ActiveRecord
  class IrreversibleMigration < StandardError; end
  class Migration
    def self.[](_version); self; end
    attr_reader :tables, :indices, :foreign_keys, :checks, :operations
    attr_accessor :populated
    def initialize
      @tables = {}; @indices = []; @foreign_keys = []; @checks = []; @operations = []; @populated = false
    end
    Table = Struct.new(:columns) do
      def method_missing(name, *args, **options)
        if name == :timestamps
          %i[created_at updated_at].each { |v| columns[v] = { type: :datetime, options: { null: false } } }
        else
          args.each { |v| columns[v] = { type: name, options: options } }
        end
      end
      def respond_to_missing?(*); true; end
    end
    def create_table(name, **options)
      @tables[name.to_s] = { id: { type: :bigint, options: { null: false } } }
      yield Table.new(@tables[name.to_s])
    end
    def add_index(table, columns, **opts); @indices << { table: table.to_s, columns: Array(columns), **opts }; end
    def add_foreign_key(table, target, **opts); @foreign_keys << { table: table.to_s, target: target.to_s, **opts }; end
    def add_check_constraint(table, expression, **opts); @checks << { table: table.to_s, expression: expression, **opts }; end
    def add_column(table, name, type, **opts); @operations << [:add_column, table.to_s, name, type, opts]; end
    def remove_foreign_key(*args, **opts); @operations << [:remove_foreign_key, args, opts]; end
    def remove_column(*args); @operations << [:remove_column, args]; end
    def drop_table(*args); @operations << [:drop_table, args]; end
    def select_value(*); @populated; end
    def quote_table_name(name); %Q["#{name}"]; end
  end
end
root = ARGV.shift || File.expand_path('../..', __dir__)
load File.join(root, 'db/migrate/20260928120000_add_jrc_service_desk_lifecycle.rb')
load File.join(root, 'db/migrate/20260925190100_create_jrc_service_desk_core.rb')
RESULT = AddJrcServiceDeskLifecycle.new.tap(&:up)
BASE = CreateJrcServiceDeskCore.new.tap(&:up)
File.write(ENV['JRC_SD_STRUCTURE_OUTPUT'], JSON.pretty_generate({ tables: RESULT.tables, indices: RESULT.indices, foreign_keys: RESULT.foreign_keys, checks: RESULT.checks, operations: RESULT.operations })) if ENV['JRC_SD_STRUCTURE_OUTPUT']
class LifecycleMigrationDeclarationTest < Minitest::Test
  def test_only_seven_owned_tables
    assert_equal 7, RESULT.tables.size
    RESULT.tables.each do |name, columns|
      assert name.start_with?('jrc_service_desk_')
      assert_equal false, columns.fetch(:account_id)[:options][:null]
      assert_equal false, columns.fetch(:unit_id)[:options][:null]
      assert_equal :integer, columns[:account_id][:type]
      assert_equal :bigint, columns[:unit_id][:type]
    end
  end
  def test_all_composite_foreign_keys_target_real_unique_keys
    known = BASE.indices + RESULT.indices
    RESULT.foreign_keys.each do |fk|
      next if fk[:target] == 'accounts'
      target_cols = Array(fk[:primary_key])
      assert known.any? { |i| i[:table] == fk[:target] && i[:unique] && i[:columns] == target_cols }, "Missing key for #{fk}"
      assert_equal :account_id, Array(fk[:column]).first
      assert_equal target_cols.length, Array(fk[:column]).length
    end
  end
  def test_identifiers_are_short_and_unique
    names = RESULT.indices.map { |i| i[:name] } + RESULT.checks.map { |i| i[:name] } + RESULT.foreign_keys.filter_map { |i| i[:name] }
    assert_equal names.size, names.uniq.size
    names.each { |name| assert name.bytesize <= 63, name }
  end
  def test_default_false_not_an_implicit_policy_or_service
    assert_equal false, RESULT.tables['jrc_service_desk_services'][:active][:options][:default]
    assert_equal false, RESULT.tables['jrc_service_desk_lifecycle_policies'][:enabled][:options][:default]
    assert_equal [:service_id, :lifecycle_policy_version_id], RESULT.operations.select { |op| op.first == :add_column }.map { |op| op[2] }
    refute RESULT.operations.any? { |op| op.first.to_s.start_with?('remove') }
  end
  def test_partial_uniqueness_and_idempotency_are_declared
    assert RESULT.indices.any? { |i| i[:unique] && i[:where] == 'service_id IS NULL' }
    assert RESULT.indices.any? { |i| i[:unique] && i[:where] == 'service_id IS NOT NULL' }
    assert RESULT.indices.any? { |i| i[:unique] && i[:where] == 'ended_at IS NULL' }
    assert RESULT.indices.any? { |i| i[:unique] && i[:columns] == %i[account_id unit_id ticket_id actor_membership_id request_key] }
  end
  def test_pause_null_pair_and_clock_completion_checks_are_present
    assert RESULT.checks.any? { |c| c[:expression].include?('(ended_at IS NULL) = (ended_by_membership_id IS NULL)') }
    assert RESULT.checks.any? { |c| c[:expression].include?("(state = 'completed') = (achieved_at IS NOT NULL)") }
  end
  def test_populated_rollback_refuses_before_any_drop_or_remove
    migration = AddJrcServiceDeskLifecycle.new; migration.populated = true
    assert_raises(ActiveRecord::IrreversibleMigration) { migration.down }
    assert_empty migration.operations
  end
  def test_empty_rollback_reverses_only_new_resources
    migration = AddJrcServiceDeskLifecycle.new; migration.down
    dropped = migration.operations.select { |op| op.first == :drop_table }.map { |op| op[1].first }
    assert_equal RESULT.tables.keys.reverse, dropped
    assert_equal 2, migration.operations.count { |op| op.first == :remove_column }
  end
end
