# frozen_string_literal: true

require 'json'
require 'digest'

# Fingerprints only optional classification receipts and the two new guards; no previous guard is replaced.
class JrcContactCenter::EndingConfirmationSchemaReceipt
  TABLES = %w[jrc_contact_center_ending_reason_confirmations].freeze
  COLUMNS = {
    TABLES[0] => %w[id account_id qualification_id source_qualification_id actor_account_user_id actor_user_id catalogue_id
                    request_key reason_code reason_label input_digest payload integrity_sha256 created_at]
  }.freeze
  FUNCTIONS = %w[cc_ending_confirmation_guard cc_ending_confirmation_qualification_guard].freeze
  TRIGGERS = %w[cc_ending_confirmation_immutable cc_ending_confirmation_fixed_reason].freeze

  def initialize(connection)
    @connection = connection
  end

  def stamp!
    receipt = token
    TABLES.each { |table| @connection.change_table_comment(table, receipt) }
  end

  def verify!
    valid = complete_structure? && TABLES.all? { |table| @connection.table_comment(table) == token }
    raise ActiveRecord::MigrationError, 'Unexpected ending confirmation schema; preserve history and investigate' unless valid
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
    "jrc_cc_ending_confirmation_v1:#{Digest::SHA256.hexdigest(JSON.generate([structure, constraints, functions, triggers]))}"
  end

  def relations
    (TABLES + %w[jrc_contact_center_qualifications]).map { |name| "#{@connection.quote(name)}::regclass" }.join(',')
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
