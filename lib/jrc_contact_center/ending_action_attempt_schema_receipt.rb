# frozen_string_literal: true

require 'json'
require 'digest'

# Exact owned technical history. Never normalize an unknown schema, restamp a
# mismatch or use a successful migration as authorization to run an automation.
class JrcContactCenter::EndingActionAttemptSchemaReceipt
  ATTEMPTS = 'jrc_contact_center_ending_action_attempts'
  OUTCOMES = 'jrc_contact_center_ending_action_attempt_outcomes'
  TABLES = [ATTEMPTS, OUTCOMES].freeze
  COLUMNS = {
    ATTEMPTS => %w[id account_id origin_id readiness_id version_id actor_account_user_id actor_user_id rule_code
                   destination_kind request_key created_at integrity_sha256],
    OUTCOMES => %w[id account_id attempt_id execution_id outcome result_code created_at integrity_sha256]
  }.freeze

  def initialize(connection)
    @connection = connection
  end

  def stamp!
    value = token
    TABLES.each { |table| @connection.change_table_comment(table, value) }
  end

  def verify!
    valid = valid_structure? && valid_references? && TABLES.all? { |table| @connection.table_comment(table) == token }
    raise ActiveRecord::MigrationError, 'Unexpected ending attempt history; preserve evidence and investigate' unless valid
  end

  private

  def valid_structure?
    valid = COLUMNS.all? { |table, names| @connection.table_exists?(table) && @connection.columns(table).map(&:name).sort == names.sort }
    expected = [['cc_ending_attempt_immutable', ATTEMPTS], ['cc_ending_attempt_outcome_immutable', OUTCOMES]]
    valid && functions.length == 2 && triggers.map { |row| row.first(2) } == expected
  end

  def valid_references?
    names = %w[cc_ending_attempt_origin_fk cc_ending_attempt_readiness_fk cc_ending_outcome_attempt_fk cc_ending_outcome_execution_fk]
    keys = TABLES.flat_map { |table| @connection.foreign_keys(table) }
    keys.length == 6 && keys.count { |key| names.include?(key.name) && key.deferrable == :deferred } == 4
  end

  def structure
    TABLES.map do |table|
      columns = @connection.columns(table).map { |row| [row.name, row.sql_type, row.null, row.default, row.default_function, row.collation] }
      indexes = @connection.indexes(table).map { |row| [row.name, row.columns, row.unique, row.where] }.sort
      [table, columns, indexes]
    end
  end

  def constraints
    @connection.select_rows(<<~SQL.squish)
      SELECT c.relname, k.conname, pg_get_constraintdef(k.oid, true)
      FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid
      WHERE k.conrelid IN ('#{ATTEMPTS}'::regclass, '#{OUTCOMES}'::regclass) ORDER BY c.relname, k.conname
    SQL
  end

  def functions
    @connection.select_rows(<<~SQL.squish)
      SELECT proname, pg_get_functiondef(oid) FROM pg_proc
      WHERE proname IN ('cc_ending_attempt_guard', 'cc_ending_attempt_outcome_guard')
      AND pronamespace = (SELECT relnamespace FROM pg_class WHERE oid = '#{ATTEMPTS}'::regclass) ORDER BY proname
    SQL
  end

  def triggers
    @connection.select_rows(<<~SQL.squish)
      SELECT t.tgname, c.relname, pg_get_triggerdef(t.oid, true) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
      WHERE NOT t.tgisinternal AND t.tgrelid IN ('#{ATTEMPTS}'::regclass, '#{OUTCOMES}'::regclass) ORDER BY t.tgname
    SQL
  end

  def token
    "jrc_cc_ending_attempt_history_v1:#{Digest::SHA256.hexdigest(JSON.generate([structure, constraints, functions, triggers]))}"
  end
end
