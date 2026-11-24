# frozen_string_literal: true

# PRIVATE CANDIDATE. Installation creates an empty receipt ledger, no effect,
# hook, job, readiness or retroactive execution. Requires source admission.
class CreateContactCenterEndingActionExecutions < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_ending_action_executions
  SQL = 'db/functions/20261124000000_contact_center_ending_executions.sql'
  SOURCES = {
    'db/functions/20261124000000_contact_center_ending_executions.sql' => '18f93d4daf3cd6210ca57a914787baf164867edb41f186c35169f167981bf675',
    'lib/jrc_contact_center/ending_action_execution_schema_receipt.rb' => '28ffc5a421d7060f0aa0c1d916e97f4e4f0d7f09eed000ddbd2142727d4d8e16'
  }.freeze

  def up
    load_sources!
    receipt = JrcContactCenter::EndingActionExecutionSchemaReceipt.new(connection)
    return receipt.verify! if table_exists?(TABLE)

    create_receipts
    create_references
    create_constraints
    execute File.read(Rails.root.join(SQL))
    receipt.stamp!
    receipt.verify!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Destination success history requires a separately reviewed rollback'
  end

  private

  def load_sources!
    raise ActiveRecord::MigrationError, 'Unreviewed ending success candidate' unless SOURCES.keys.include?(SQL)

    SOURCES.each do |path, expected|
      raise ActiveRecord::MigrationError, 'Unreviewed ending success source; preserve history' unless
        Digest::SHA256.file(Rails.root.join(path)).hexdigest == expected
    end
    require Rails.root.join('lib/jrc_contact_center/ending_action_execution_schema_receipt')
  end

  def create_receipts
    create_table TABLE do |table|
      table.bigint :account_id, :origin_id, :readiness_id, :version_id, :actor_account_user_id, :actor_user_id, :target_id, :trigger_id, null: false
      table.string :rule_code, null: false, limit: 100
      table.string :destination_kind, :trigger_kind, null: false, limit: 50
      table.uuid :request_key, null: false
      table.datetime :triggered_at, null: false
      table.datetime :created_at, null: false
      table.string :integrity_sha256, null: false, limit: 64
    end
    add_index TABLE, [:account_id, :origin_id, :rule_code, :destination_kind], unique: true, name: 'cc_ending_success_once'
    add_index TABLE, [:account_id, :request_key], unique: true, name: 'cc_ending_success_request'
    add_index TABLE, [:id, :account_id], unique: true, name: 'cc_ending_success_account'
  end

  def create_references
    add_foreign_key TABLE, :jrc_contact_center_ending_scope_accounts, column: :account_id, primary_key: :account_id, on_delete: :cascade
    add_foreign_key TABLE, :jrc_contact_center_ending_action_origins,
                    column: [:origin_id, :account_id], primary_key: [:id, :account_id], deferrable: :deferred, name: 'cc_ending_success_origin_fk'
    add_foreign_key TABLE, :jrc_contact_center_ending_action_readinesses,
                    column: [:readiness_id, :account_id], primary_key: [:id, :account_id],
                    deferrable: :deferred, name: 'cc_ending_success_readiness_fk'
  end

  def create_constraints
    names = %w[account_id origin_id readiness_id version_id actor_account_user_id actor_user_id target_id trigger_id]
    add_check_constraint TABLE, names.map { |name| "#{name} > 0" }.join(' AND '), name: 'cc_ending_success_identity'
    add_check_constraint TABLE, "integrity_sha256 ~ '^[0-9a-f]{64}$'", name: 'cc_ending_success_digest'
    add_check_constraint TABLE, "destination_kind = 'project_task' AND btrim(rule_code) <> ''", name: 'cc_ending_success_destination'
    kinds = "ARRAY['ending_reason_confirmation'::text, 'ending_action_completion'::text]"
    add_check_constraint TABLE, "trigger_kind::text = ANY (#{kinds})", name: 'cc_ending_success_trigger'
  end
end
