# frozen_string_literal: true

require 'digest'

# Empty additive receipt. No grants, data backfill, task copy or operational activation.
class CreateContactCenterRecordingTaskLinks < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_recording_task_links
  SQL = 'db/functions/20261127003000_contact_center_recording_task_links.sql'
  SQL_SHA256 = '7f013d1a932a7832e56b34f02d1d0cd12b4d961c6663922d64817a5c6ff7c238'

  def up
    verify_sources!
    require Rails.root.join('lib/jrc_contact_center/recording_task_schema_receipt')
    receipt = JrcContactCenter::RecordingTaskSchemaReceipt.new(connection)
    return receipt.verify! if table_exists?(TABLE)

    create_receipt_table
    create_constraints
    execute File.read(Rails.root.join(SQL))
    receipt.stamp!
    receipt.verify!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Recording task history requires a separately reviewed rollback'
  end

  private

  def verify_sources!
    valid_sql = Digest::SHA256.file(Rails.root.join(SQL)).hexdigest == SQL_SHA256
    raise ActiveRecord::MigrationError, 'Unreviewed recording task source' unless valid_sql

    receipt_path = 'lib/jrc_contact_center/recording_task_schema_receipt.rb'
    expected = 'e33b56fa7770ec904672061f1bf27e4f47b89b906a84cc8f73d9320a08e60537'
    return if Digest::SHA256.file(Rails.root.join(receipt_path)).hexdigest == expected

    raise ActiveRecord::MigrationError, 'Unreviewed recording task schema verifier'
  end

  def create_receipt_table
    create_table TABLE do |table|
      table.bigint :account_id, :recording_id, :call_session_id, :project_id, :task_id, :created_by_id, :actor_account_user_id, null: false
      table.uuid :idempotency_key, null: false
      table.string :request_fingerprint, null: false, limit: 64
      table.jsonb :scope_snapshot, null: false
      table.datetime :created_at, null: false
    end
  end

  def create_constraints
    add_foreign_key TABLE, :accounts, column: :account_id, on_delete: :cascade, name: 'cc_recording_task_account_fk'
    add_index TABLE, %i[account_id idempotency_key], unique: true, name: 'cc_recording_task_request'
    add_index TABLE, %i[account_id recording_id id], name: 'cc_recording_task_source'
    add_check_constraint TABLE, "request_fingerprint ~ '^[0-9a-f]{64}$'", name: 'cc_recording_task_fingerprint'
    add_check_constraint TABLE, "jsonb_typeof(scope_snapshot) = 'object'", name: 'cc_recording_task_scope'
    identity_constraint
  end

  def identity_constraint
    fields = %w[account_id recording_id call_session_id project_id task_id created_by_id actor_account_user_id]
    add_check_constraint TABLE, fields.map { |field| "#{field} > 0" }.join(' AND '), name: 'cc_recording_task_identity'
  end
end
