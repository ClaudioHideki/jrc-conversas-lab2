# frozen_string_literal: true

require 'digest'
require 'json'

# Same native schema-receipt pattern as the existing immutable ending history, scoped to one additive table.
class JrcContactCenter::QualityReviewSchemaReceipt
  TABLE = 'jrc_contact_center_quality_review_revisions'
  COLUMNS = %w[id account_id recording_id call_session_id actor_account_user_id actor_user_id revision request_key
               source_sha256 input_sha256 original_analysis reviewed_values scope_snapshot created_at].freeze
  FUNCTIONS = %w[cc_quality_review_append cc_quality_review_immutable].freeze
  TRIGGERS = %w[cc_quality_review_append_guard cc_quality_review_immutable_guard].freeze

  def initialize(connection)
    @connection = connection
  end

  def stamp!
    verify_structure!
    @connection.change_table_comment(TABLE, token)
  end

  def verify!
    verify_structure!
    return if @connection.table_comment(TABLE) == token

    raise ActiveRecord::MigrationError, 'Unknown quality review schema; preserve existing history'
  end

  private

  def verify_structure!
    verify_columns!
    verify_account_reference!
    valid = functions.map(&:first) == FUNCTIONS && triggers.map(&:first) == TRIGGERS
    raise ActiveRecord::MigrationError, 'Unknown quality review references or guards' unless valid
  end

  def verify_columns!
    valid = @connection.table_exists?(TABLE) && @connection.columns(TABLE).map(&:name).sort == COLUMNS.sort
    raise ActiveRecord::MigrationError, 'Incomplete quality review schema' unless valid
  end

  def verify_account_reference!
    keys = @connection.foreign_keys(TABLE)
    valid = keys.length == 1 && keys.first.to_table == 'accounts' && keys.first.on_delete == :cascade
    raise ActiveRecord::MigrationError, 'Unknown quality review references or guards' unless valid
  end

  def structure
    columns = @connection.columns(TABLE).map { |row| [row.name, row.sql_type, row.null, row.default, row.default_function] }
    indexes = @connection.indexes(TABLE).map { |row| [row.name, row.columns, row.unique, row.where] }.sort
    [columns, indexes]
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
      WHERE proname IN ('cc_quality_review_append', 'cc_quality_review_immutable')
      AND pronamespace = (SELECT relnamespace FROM pg_class WHERE oid = '#{TABLE}'::regclass) ORDER BY proname
    SQL
  end

  def triggers
    @connection.select_rows(<<~SQL.squish)
      SELECT tgname, pg_get_triggerdef(oid, true), tgenabled FROM pg_trigger
      WHERE tgrelid = '#{TABLE}'::regclass AND NOT tgisinternal ORDER BY tgname
    SQL
  end

  def token
    "jrc_cc_quality_review_v1:#{Digest::SHA256.hexdigest(JSON.generate([structure, constraints, functions, triggers]))}"
  end
end
