# frozen_string_literal: true

require 'digest'
require 'json'

# Separate additive observation domain; never rewrites the nine preceding schema receipts.
class JrcContactCenter::AudioInspectionSchemaReceipt
  TABLE = 'jrc_contact_center_audio_inspections'
  FUNCTION = 'cc_institutional_audio_inspection_guard'
  COLUMNS = %w[id account_id unit_id audio_version_id source_blob_id created_by_id attempt idempotency_key input_digest
               expected_sha256 observed_sha256 state probe_state scanner_adapter decoder_version metadata observed_at created_at].freeze

  def initialize(connection)
    @connection = connection
  end

  def stamp!
    @connection.change_table_comment(TABLE, token)
  end

  def verify!
    valid = complete_structure? && @connection.table_comment(TABLE) == token
    raise ActiveRecord::MigrationError, 'Unexpected institutional audio inspection schema; preserve history' unless valid
  end

  private

  def complete_structure?
    @connection.table_exists?(TABLE) && @connection.columns(TABLE).map(&:name).sort == COLUMNS.sort &&
      functions.length == 1 && triggers.length == 1 && triggers.first[1] == 'O'
  end

  def token
    columns = @connection.columns(TABLE).map { |row| [row.name, row.sql_type, row.null, row.default, row.default_function, row.collation] }
    indexes = @connection.indexes(TABLE).map { |row| [row.name, row.columns, row.unique, row.where, row.orders] }.sort
    "jrc_cc_audio_inspections_v1:#{Digest::SHA256.hexdigest(JSON.generate([columns, indexes, constraints, functions, triggers]))}"
  end

  def constraints
    @connection.select_rows(<<~SQL.squish)
      SELECT conname, pg_get_constraintdef(oid, true) FROM pg_constraint
      WHERE conrelid = '#{TABLE}'::regclass ORDER BY conname
    SQL
  end

  def functions
    @connection.select_rows(<<~SQL.squish)
      SELECT proname, pg_get_functiondef(oid) FROM pg_proc
      WHERE proname = '#{FUNCTION}'
        AND pronamespace = (SELECT relnamespace FROM pg_class WHERE oid = '#{TABLE}'::regclass)
      ORDER BY proname
    SQL
  end

  def triggers
    @connection.select_rows(<<~SQL.squish)
      SELECT tgname, tgenabled, tgtype, pg_get_triggerdef(oid, true) FROM pg_trigger
      WHERE NOT tgisinternal AND tgrelid = '#{TABLE}'::regclass AND tgname = '#{FUNCTION}' ORDER BY tgname
    SQL
  end
end
