# frozen_string_literal: true

require 'json'
require 'digest'

# Private unapplied receipt. Owns only the two new evidence tables and its exact
# leg columns/constraint/index; native call/reason/qualification guards stay unchanged.
class JrcContactCenter::EndingExecutionOriginSchemaReceipt
  ORIGINS = 'jrc_contact_center_ending_action_origins'
  COMPLETIONS = 'jrc_contact_center_ending_action_completions'
  LEGS = 'jrc_contact_center_call_legs'
  COLUMNS = {
    ORIGINS => %w[id account_id qualification_id source_qualification_id origin_event_id call_session_id call_leg_id
                  actor_account_user_id actor_user_id version_id ending_reason_catalog_id queue_scope_version_id queue_id
                  unit_id issuer_company_id business_unit_id integrity_sha256 private_origin_evidence created_at],
    COMPLETIONS => %w[id account_id origin_id source_qualification_id reason_code outcome_code integrity_sha256
                      private_completion_evidence completed_at created_at],
    LEGS => %w[ending_action_scope_version_id ending_action_captured_started_at]
  }.freeze
  FUNCTIONS = %w[cc_ending_action_leg_guard cc_ending_action_origin_guard cc_ending_action_capture_pending
                 cc_ending_action_completion_document cc_ending_action_completion_guard cc_ending_action_completion_matches
                 cc_ending_action_capture_completion].freeze
  TRIGGERS = {
    'cc_ending_action_leg_capture' => LEGS,
    'cc_ending_action_origin_immutable' => ORIGINS,
    'cc_ending_action_pending_origin' => 'jrc_contact_center_agent_state_events',
    'cc_ending_action_completion_immutable' => COMPLETIONS,
    'cc_ending_action_native_completion' => 'jrc_contact_center_qualifications'
  }.freeze
  LEG_CONSTRAINTS = %w[cc_ending_execution_leg_capture cc_ending_execution_leg_scope_fk].freeze

  def initialize(connection)
    @connection = connection
  end

  def stamp!
    [ORIGINS, COMPLETIONS].each { |table| @connection.change_table_comment(table, token) }
  end

  def verify!
    valid = COLUMNS.keys.all? { |table| @connection.table_exists?(table) }
    valid &&= valid_columns? && valid_references?
    valid &&= valid_guards? && valid_stamps?
    raise ActiveRecord::MigrationError, 'Unexpected ending execution origin schema; preserve evidence and investigate' unless valid
  end

  private

  def valid_guards?
    functions.length == FUNCTIONS.length && triggers.map { |row| row.first(2) }.sort == TRIGGERS.to_a.sort
  end

  def valid_stamps?
    [ORIGINS, COMPLETIONS].all? { |table| @connection.table_comment(table) == token }
  end

  def valid_columns?
    [ORIGINS, COMPLETIONS].all? { |table| @connection.columns(table).map(&:name).sort == COLUMNS.fetch(table).sort } &&
      columns(LEGS).map(&:name).sort == COLUMNS.fetch(LEGS).sort
  end

  def valid_references?
    expected = %w[jrc_contact_center_ending_scope_accounts jrc_contact_center_qualifications
                  jrc_contact_center_ending_action_versions jrc_contact_center_ending_action_queue_scopes]
    @connection.foreign_keys(ORIGINS).map(&:to_table).sort == expected.sort &&
      @connection.foreign_keys(COMPLETIONS).map(&:to_table).sort == [ORIGINS, 'jrc_contact_center_ending_scope_accounts'].sort &&
      @connection.foreign_keys(LEGS).count { |key| key.name == 'cc_ending_execution_leg_scope_fk' && key.deferrable == :deferred } == 1
  end

  def columns(table)
    selected = @connection.columns(table)
    table == LEGS ? selected.select { |row| COLUMNS.fetch(LEGS).include?(row.name) } : selected
  end

  def structure
    COLUMNS.keys.map do |table|
      values = columns(table).map { |row| [row.name, row.sql_type, row.null, row.default, row.default_function, row.collation] }
      indexes = @connection.indexes(table)
      indexes = indexes.select { |row| row.name == 'cc_ending_execution_leg_scope' } if table == LEGS
      [table, values, indexes.map { |row| [row.name, row.columns, row.unique, row.where] }.sort]
    end
  end

  def constraints
    @connection.select_rows(<<~SQL.squish)
      SELECT c.relname, k.conname, pg_get_constraintdef(k.oid, true)
      FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid
      WHERE k.conrelid IN ('#{ORIGINS}'::regclass, '#{COMPLETIONS}'::regclass)
        OR (k.conrelid = '#{LEGS}'::regclass AND k.conname IN (#{quoted(LEG_CONSTRAINTS)}))
      ORDER BY c.relname, k.conname
    SQL
  end

  def functions
    @connection.select_rows(<<~SQL.squish)
      SELECT proname, pg_get_functiondef(oid) FROM pg_proc WHERE proname IN (#{quoted(FUNCTIONS)})
      AND pronamespace = (SELECT relnamespace FROM pg_class WHERE oid = '#{ORIGINS}'::regclass) ORDER BY proname
    SQL
  end

  def triggers
    @connection.select_rows(<<~SQL.squish)
      SELECT t.tgname, c.relname, pg_get_triggerdef(t.oid, true)
      FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
      WHERE NOT t.tgisinternal AND t.tgname IN (#{quoted(TRIGGERS.keys)})
        AND c.relnamespace = (SELECT relnamespace FROM pg_class WHERE oid = '#{ORIGINS}'::regclass)
      ORDER BY t.tgname, c.relname
    SQL
  end

  def quoted(names)
    names.map { |name| @connection.quote(name) }.join(',')
  end

  def token
    "jrc_cc_ending_execution_origins_v1:#{Digest::SHA256.hexdigest(JSON.generate([structure, constraints, functions, triggers]))}"
  end
end
