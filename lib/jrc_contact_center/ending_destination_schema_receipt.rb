# frozen_string_literal: true

require 'digest'
require 'json'

# Owned additive technical history. Unknown or incomplete schemas are refused;
# verifying an existing installation never stamps or normalizes it.
class JrcContactCenter::EndingDestinationSchemaReceipt
  CONSENTS = 'jrc_contact_center_ending_destination_consents'
  ATTEMPTS = 'jrc_contact_center_ending_destination_attempts'
  EXECUTIONS = 'jrc_contact_center_ending_destination_executions'
  OUTCOMES = 'jrc_contact_center_ending_destination_outcomes'
  TABLES = [CONSENTS, ATTEMPTS, EXECUTIONS, OUTCOMES].freeze
  IDENTITY = %w[account_id origin_id readiness_id version_id actor_account_user_id actor_user_id rule_code
                destination_kind operation rule_sha256 trigger_kind trigger_id triggered_at].freeze
  COLUMNS = {
    CONSENTS => %w[id request_key created_at integrity_sha256] + IDENTITY,
    ATTEMPTS => %w[id consent_id retry_of_id retry_requested_by_account_user_id request_key effect_key created_at integrity_sha256] + IDENTITY,
    EXECUTIONS => %w[id attempt_id request_key effect_key target_type target_id native_audit_id native_version
                     created_at integrity_sha256] + IDENTITY,
    OUTCOMES => %w[id account_id attempt_id execution_id outcome result_code created_at integrity_sha256]
  }.freeze
  FUNCTIONS = %w[cc_ending_destination_context cc_ending_destination_consent_guard cc_ending_destination_attempt_guard
                 cc_ending_destination_execution_guard cc_ending_destination_outcome_guard].freeze
  TRIGGERS = [['cc_typed_attempt_immutable', ATTEMPTS], ['cc_typed_consent_immutable', CONSENTS],
              ['cc_typed_execution_immutable', EXECUTIONS], ['cc_typed_outcome_immutable', OUTCOMES]].freeze
  REFERENCES = %w[cc_typed_consent_origin_fk cc_typed_consent_ready_fk cc_typed_attempt_origin_fk cc_typed_attempt_ready_fk
                  cc_typed_attempt_consent_fk cc_typed_attempt_retry_fk cc_typed_execution_attempt_fk
                  cc_typed_outcome_attempt_fk cc_typed_outcome_execution_fk].freeze

  def initialize(connection)
    @connection = connection
  end

  def stamp!
    verify_structure!
    value = token
    TABLES.each { |table| @connection.change_table_comment(table, value) }
  end

  def verify!
    verify_structure!
    value = token
    return if TABLES.all? { |table| @connection.table_comment(table) == value }

    raise ActiveRecord::MigrationError, 'Unexpected typed ending history; preserve evidence and investigate'
  end

  private

  def verify_structure!
    raise ActiveRecord::MigrationError, 'Incomplete typed ending history; preserve existing schema' unless complete_columns?

    valid = complete_references? && functions.map(&:first).sort == FUNCTIONS.sort && triggers.map { |row| row.first(2) } == TRIGGERS
    raise ActiveRecord::MigrationError, 'Unknown typed ending history references or functions' unless valid
  end

  def complete_columns?
    COLUMNS.all? { |table, columns| @connection.table_exists?(table) && @connection.columns(table).map(&:name).sort == columns.sort }
  end

  def complete_references?
    keys = TABLES.flat_map { |table| @connection.foreign_keys(table) }
    keys.length == 13 && keys.count { |key| REFERENCES.include?(key.name) && key.deferrable == :deferred } == 9
  end

  def structure
    TABLES.map do |table|
      columns = @connection.columns(table).map { |row| [row.name, row.sql_type, row.null, row.default, row.default_function, row.collation] }
      indexes = @connection.indexes(table).map { |row| [row.name, row.columns, row.unique, row.where] }.sort
      [table, columns, indexes]
    end
  end

  def table_oids
    TABLES.map { |table| "'#{table}'::regclass" }.join(', ')
  end

  def constraints
    @connection.select_rows(<<~SQL.squish)
      SELECT c.relname, k.conname, pg_get_constraintdef(k.oid, true)
      FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid
      WHERE k.conrelid IN (#{table_oids}) ORDER BY c.relname, k.conname
    SQL
  end

  def functions
    names = FUNCTIONS.map { |name| "'#{name}'" }.join(', ')
    @connection.select_rows(<<~SQL.squish)
      SELECT proname, pg_get_functiondef(oid) FROM pg_proc WHERE proname IN (#{names})
      AND pronamespace = (SELECT relnamespace FROM pg_class WHERE oid = '#{CONSENTS}'::regclass) ORDER BY proname
    SQL
  end

  def triggers
    @connection.select_rows(<<~SQL.squish)
      SELECT t.tgname, c.relname, pg_get_triggerdef(t.oid, true), t.tgenabled FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid WHERE NOT t.tgisinternal AND t.tgrelid IN (#{table_oids}) ORDER BY t.tgname
    SQL
  end

  def token
    "jrc_cc_typed_ending_history_v1:#{Digest::SHA256.hexdigest(JSON.generate([structure, constraints, functions, triggers]))}"
  end
end
