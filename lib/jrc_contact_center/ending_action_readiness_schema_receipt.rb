# frozen_string_literal: true

require 'json'
require 'digest'

# Receipt for owned prospective metadata only; does not rewrite prior ledgers.
class JrcContactCenter::EndingActionReadinessSchemaReceipt
  TABLE = 'jrc_contact_center_ending_action_readinesses'
  COLUMNS = %w[id account_id version_id actor_account_user_id actor_user_id cutoff_call_id cutoff_leg_id
               request_key rule_code source_timezone rule_sha256 created_at].freeze
  FUNCTIONS = %w[cc_ending_action_readiness_guard cc_ending_action_readiness_matches].freeze

  def initialize(connection)
    @connection = connection
  end

  def stamp!
    @connection.change_table_comment(TABLE, token)
  end

  def verify!
    valid = valid_structure? && valid_references? && @connection.table_comment(TABLE) == token
    raise ActiveRecord::MigrationError, 'Unexpected ending readiness schema; preserve history and investigate' unless valid
  end

  private

  def valid_structure?
    columns_valid = @connection.table_exists?(TABLE) && @connection.columns(TABLE).map(&:name).sort == COLUMNS.sort
    columns_valid && functions.length == FUNCTIONS.length &&
      triggers.map { |row| row.first(2) } == [['cc_ending_action_readiness_immutable', TABLE]]
  end

  def valid_references?
    keys = @connection.foreign_keys(TABLE)
    expected = %w[jrc_contact_center_ending_scope_accounts jrc_contact_center_ending_action_versions]
    keys.map(&:to_table).sort == expected.sort &&
      keys.count { |key| key.name == 'cc_ending_readiness_version_fk' && key.deferrable == :deferred } == 1
  end

  def structure
    columns = @connection.columns(TABLE).map { |row| [row.name, row.sql_type, row.null, row.default, row.default_function, row.collation] }
    indexes = @connection.indexes(TABLE).map { |row| [row.name, row.columns, row.unique, row.where] }.sort
    [[TABLE, columns, indexes]]
  end

  def constraints
    @connection.select_rows(<<~SQL.squish)
      SELECT c.relname, k.conname, pg_get_constraintdef(k.oid, true)
      FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid
      WHERE k.conrelid = '#{TABLE}'::regclass ORDER BY c.relname, k.conname
    SQL
  end

  def functions
    @connection.select_rows(<<~SQL.squish)
      SELECT proname, pg_get_functiondef(oid) FROM pg_proc WHERE proname IN (#{quoted(FUNCTIONS)})
      AND pronamespace = (SELECT relnamespace FROM pg_class WHERE oid = '#{TABLE}'::regclass) ORDER BY proname
    SQL
  end

  def triggers
    @connection.select_rows(<<~SQL.squish)
      SELECT t.tgname, c.relname, pg_get_triggerdef(t.oid, true) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
      WHERE NOT t.tgisinternal AND t.tgrelid = '#{TABLE}'::regclass
      ORDER BY t.tgname
    SQL
  end

  def quoted(names)
    names.map { |name| @connection.quote(name) }.join(',')
  end

  def token
    "jrc_cc_ending_action_readiness_v1:#{Digest::SHA256.hexdigest(JSON.generate([structure, constraints, functions, triggers]))}"
  end
end
