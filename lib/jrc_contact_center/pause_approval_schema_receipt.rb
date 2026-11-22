# frozen_string_literal: true

require 'json'
require 'digest'

# Fingerprints only the additive all-scope pause source evidence and its immutable/completeness guards.
class JrcContactCenter::PauseApprovalSchemaReceipt
  TABLES = %w[jrc_contact_center_pause_approval_reviews jrc_contact_center_pause_approval_scopes].freeze
  COLUMNS = {
    TABLES[0] => %w[id account_id deferred_pause_request_id actor_account_user_id actor_user_id payload context_digest created_at],
    TABLES[1] => %w[id account_id review_id issuer_company_id business_unit_id unit_ids created_at]
  }.freeze
  FUNCTIONS = %w[cc_pause_approval_evidence_guard cc_pause_approval_scope_completeness].freeze
  TRIGGERS = %w[cc_pause_approval_review_guard cc_pause_approval_scope_guard
                cc_pause_approval_review_complete cc_pause_approval_scope_complete].freeze

  def initialize(connection)
    @connection = connection
  end

  def stamp!
    receipt = token
    TABLES.each { |table| @connection.change_table_comment(table, receipt) }
  end

  def verify!
    valid = complete_structure? && TABLES.all? { |table| @connection.table_comment(table) == token }
    raise ActiveRecord::MigrationError, 'Unexpected pause approval evidence schema; preserve history and investigate' unless valid
  end

  private

  def complete_structure?
    return false unless TABLES.all? { |table| @connection.table_exists?(table) }
    return false unless COLUMNS.all? { |table, names| @connection.columns(table).map(&:name).sort == names.sort }

    functions.length == FUNCTIONS.length && triggers.length == TRIGGERS.length
  end

  def token
    structure = TABLES.map do |table|
      columns = @connection.columns(table).map { |row| [row.name, row.sql_type, row.null, row.default, row.default_function, row.collation] }
      indexes = @connection.indexes(table).map { |row| [row.name, row.columns, row.unique, row.where] }.sort
      [table, columns, indexes]
    end
    "jrc_cc_pause_approval_v1:#{Digest::SHA256.hexdigest(JSON.generate([structure, constraints, functions, triggers]))}"
  end

  def relations
    TABLES.map { |name| "#{@connection.quote(name)}::regclass" }.join(',')
  end

  def constraints
    ids = TABLES.map { |name| "#{@connection.quote(name)}::regclass" }.join(',')
    @connection.select_rows(<<~SQL.squish)
      SELECT conrelid::regclass::text, conname, pg_get_constraintdef(oid, true)
      FROM pg_constraint WHERE conrelid IN (#{ids}) ORDER BY conrelid::regclass::text, conname
    SQL
  end

  def functions
    names = FUNCTIONS.map { |name| @connection.quote(name) }.join(',')
    @connection.select_rows(<<~SQL.squish)
      SELECT proname, pg_get_functiondef(oid) FROM pg_proc
      WHERE proname IN (#{names})
        AND pronamespace = (SELECT relnamespace FROM pg_class WHERE oid = '#{TABLES.first}'::regclass)
      ORDER BY proname
    SQL
  end

  def triggers
    names = TRIGGERS.map { |name| @connection.quote(name) }.join(',')
    @connection.select_rows(<<~SQL.squish)
      SELECT tgrelid::regclass::text, tgname, pg_get_triggerdef(oid, true) FROM pg_trigger
      WHERE NOT tgisinternal AND tgrelid IN (#{relations}) AND tgname IN (#{names}) ORDER BY tgrelid::regclass::text, tgname
    SQL
  end
end
