# frozen_string_literal: true

# Prospective metadata only. No backfill, destination effect or automatic arming.
class CreateContactCenterEndingActionReadinesses < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_ending_action_readinesses
  SQL = 'db/functions/20261123235000_contact_center_ending_action_readiness.sql'
  SOURCES = {
    'db/functions/20261123235000_contact_center_ending_action_readiness.sql' => '13a6da4ca25eb6dd7f826a39070ebabb381fc776934f098504e1020c8d24d4e7',
    'lib/jrc_contact_center/ending_action_readiness_schema_receipt.rb' => '7dd62dafddbab0a574c9e89337df6629b2bafcd6700d6e0a56bdb28adfd7bce2'
  }.freeze

  def up
    load_sources!
    receipt = JrcContactCenter::EndingActionReadinessSchemaReceipt.new(connection)
    return receipt.verify! if table_exists?(TABLE)

    create_readinesses
    create_references
    create_constraints
    execute File.read(Rails.root.join(SQL))
    receipt.stamp!
    receipt.verify!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Execution readiness history requires a separately reviewed rollback'
  end

  private

  def load_sources!
    raise ActiveRecord::MigrationError, 'Unreviewed ending readiness candidate' unless SOURCES.keys.include?(SQL)

    SOURCES.each do |path, expected|
      raise ActiveRecord::MigrationError, 'Unreviewed ending readiness source; preserve history' unless
        Digest::SHA256.file(Rails.root.join(path)).hexdigest == expected
    end
    require Rails.root.join('lib/jrc_contact_center/ending_action_readiness_schema_receipt')
  end

  def create_readinesses
    create_table TABLE do |table|
      table.bigint :account_id, :version_id, :actor_account_user_id, :actor_user_id, null: false
      table.bigint :cutoff_call_id, :cutoff_leg_id, null: false
      table.uuid :request_key, null: false
      table.string :rule_code, :source_timezone, null: false, limit: 100
      table.string :rule_sha256, null: false, limit: 64
      table.datetime :created_at, null: false
    end
    add_index TABLE, [:account_id, :request_key], unique: true, name: 'cc_ending_readiness_request'
    add_index TABLE, [:id, :account_id], unique: true, name: 'cc_ending_readiness_account'
    add_index TABLE, [:account_id, :rule_code, :version_id], name: 'cc_ending_readiness_rule'
  end

  def create_references
    add_foreign_key TABLE, :jrc_contact_center_ending_scope_accounts, column: :account_id, primary_key: :account_id, on_delete: :cascade
    add_foreign_key TABLE, :jrc_contact_center_ending_action_versions, column: [:version_id, :account_id],
                    primary_key: [:id, :account_id], deferrable: :deferred, name: 'cc_ending_readiness_version_fk'
  end

  def create_constraints
    positive = 'account_id > 0 AND version_id > 0 AND actor_account_user_id > 0 AND actor_user_id > 0 AND cutoff_call_id >= 0 AND cutoff_leg_id >= 0'
    add_check_constraint TABLE, positive, name: 'cc_ending_readiness_identity'
    add_check_constraint TABLE, "rule_sha256 ~ '^[0-9a-f]{64}$'", name: 'cc_ending_readiness_digest'
    add_check_constraint TABLE, "btrim(rule_code) <> '' AND btrim(source_timezone) <> ''", name: 'cc_ending_readiness_text'
  end
end
