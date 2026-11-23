# frozen_string_literal: true

require 'json'
require 'digest'

# Unapplied WIP. This receipt covers only the owned private definition history.
class JrcContactCenter::EndingActionVersionSchemaReceipt
  TABLE = 'jrc_contact_center_ending_action_versions'
  COLUMNS = %w[id account_id revision source_audit_id actor_user_id actor_user_type head_nonce private_definition
               definition_sha256 integrity_sha256 created_at].freeze
  FUNCTIONS = %w[cc_ending_action_definition_digest cc_ending_action_version_guard].freeze
  TRIGGERS = %w[cc_ending_action_version_immutable].freeze

  def initialize(connection)
    @connection = connection
  end

  def stamp!
    @connection.change_table_comment(TABLE, token)
  end

  def verify!
    valid = @connection.table_exists?(TABLE) && @connection.columns(TABLE).map(&:name).sort == COLUMNS.sort
    valid &&= @connection.foreign_keys(TABLE).map(&:to_table) == ['accounts']
    valid &&= functions.length == FUNCTIONS.length && triggers.length == TRIGGERS.length
    valid &&= @connection.table_comment(TABLE) == token
    raise ActiveRecord::MigrationError, 'Unexpected ending action version schema; preserve history and investigate' unless valid
  end

  private

  def structure
    columns = @connection.columns(TABLE).map { |row| [row.name, row.sql_type, row.null, row.default, row.default_function, row.collation] }
    indexes = @connection.indexes(TABLE).map { |row| [row.name, row.columns, row.unique, row.where] }.sort
    [columns, indexes]
  end

  def token
    "jrc_cc_ending_action_versions_v1:#{Digest::SHA256.hexdigest(JSON.generate([structure, constraints, functions, triggers]))}"
  end

  def constraints
    @connection.select_rows(<<~SQL.squish)
      SELECT conname, pg_get_constraintdef(oid, true) FROM pg_constraint
      WHERE conrelid = '#{TABLE}'::regclass ORDER BY conname
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
    @connection.select_rows(<<~SQL.squish)
      SELECT tgname, pg_get_triggerdef(oid, true) FROM pg_trigger
      WHERE NOT tgisinternal AND tgrelid = '#{TABLE}'::regclass AND tgname IN (#{names}) ORDER BY tgname
    SQL
  end
end
