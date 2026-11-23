# frozen_string_literal: true

require 'json'
require 'digest'

# Fingerprints only the new scope ledger and its own triggers/functions. No earlier receipt is restamped.
class JrcContactCenter::EndingActionScopeSchemaReceipt
  TABLE = 'jrc_contact_center_ending_action_queue_scopes'
  ACCOUNT_TABLE = 'jrc_contact_center_ending_scope_accounts'
  TABLES = [ACCOUNT_TABLE, TABLE].freeze
  COLUMNS = %w[id account_id queue_id source_queue_id unit_id revision issuer_company_id business_unit_id scope_state
               scope_digest payload integrity_sha256 created_at].freeze
  RELATIONS = [*TABLES, 'accounts', 'jrc_contact_center_queues', 'jrc_contact_center_units', 'companies', 'jrc_crm_business_units'].freeze
  FUNCTIONS = %w[cc_ending_action_scope_id cc_ending_action_queue_scope_document cc_ending_action_queue_scope_guard
                 cc_ending_action_capture_queue_scope cc_ending_action_queue_scope_at cc_ending_action_queue_changed
                 cc_ending_action_unit_scope_changed cc_ending_action_corporate_scope_changed
                 cc_ending_action_scope_account_guard cc_ending_action_scope_account_created].freeze
  TRIGGERS = %w[cc_ending_action_queue_scope_immutable cc_ending_action_queue_scope_created cc_ending_action_queue_scope_changed
                cc_ending_action_unit_scope_changed cc_ending_action_unit_scope_deleted cc_ending_action_issuer_scope_changed
                cc_ending_action_issuer_scope_deleted cc_ending_action_business_scope_changed cc_ending_action_business_scope_deleted
                cc_ending_action_scope_account_immutable cc_ending_action_scope_account_created].freeze

  def initialize(connection)
    @connection = connection
  end

  def stamp!
    value = token
    TABLES.each { |table| @connection.change_table_comment(table, value) }
  end

  def verify!
    valid = complete_structure? && TABLES.all? { |table| @connection.table_comment(table) == token }
    raise ActiveRecord::MigrationError, 'Unexpected ending action scope schema; preserve history and investigate' unless valid
  end

  private

  def complete_structure?
    return false unless TABLES.all? { |table| @connection.table_exists?(table) }
    return false unless @connection.columns(TABLE).map(&:name).sort == COLUMNS.sort
    return false unless account_reference_structure?

    functions.length == FUNCTIONS.length && triggers.length == TRIGGERS.length
  end

  def account_reference_structure?
    @connection.columns(ACCOUNT_TABLE).map(&:name) == ['account_id'] &&
      @connection.foreign_keys(ACCOUNT_TABLE).map(&:to_table) == ['accounts'] &&
      @connection.foreign_keys(TABLE).map(&:to_table).sort == [ACCOUNT_TABLE, 'jrc_contact_center_queues'].sort
  end

  def structure
    TABLES.map do |table|
      columns = @connection.columns(table).map { |row| [row.name, row.sql_type, row.null, row.default, row.default_function, row.collation] }
      indexes = @connection.indexes(table).map { |row| [row.name, row.columns, row.unique, row.where] }.sort
      [table, columns, indexes]
    end
  end

  def token
    "jrc_cc_ending_action_scopes_v1:#{Digest::SHA256.hexdigest(JSON.generate([structure, constraints, functions, triggers]))}"
  end

  def constraints
    @connection.select_rows(<<~SQL.squish)
      SELECT conrelid::regclass::text, conname, pg_get_constraintdef(oid, true)
      FROM pg_constraint WHERE conrelid IN ('#{TABLE}'::regclass, '#{ACCOUNT_TABLE}'::regclass)
      ORDER BY conrelid::regclass::text, conname
    SQL
  end

  def functions
    names = FUNCTIONS.map { |name| @connection.quote(name) }.join(',')
    @connection.select_rows(<<~SQL.squish)
      SELECT proname, pg_get_functiondef(oid) FROM pg_proc WHERE proname IN (#{names})
        AND pronamespace = (SELECT relnamespace FROM pg_class WHERE oid = '#{TABLE}'::regclass) ORDER BY proname
    SQL
  end

  def triggers
    names = TRIGGERS.map { |name| @connection.quote(name) }.join(',')
    relations = RELATIONS.map { |name| "#{@connection.quote(name)}::regclass" }.join(',')
    @connection.select_rows(<<~SQL.squish)
      SELECT tgrelid::regclass::text, tgname, pg_get_triggerdef(oid, true) FROM pg_trigger
      WHERE NOT tgisinternal AND tgrelid IN (#{relations}) AND tgname IN (#{names}) ORDER BY tgrelid::regclass::text, tgname
    SQL
  end
end
