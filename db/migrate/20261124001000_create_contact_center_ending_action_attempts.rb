# frozen_string_literal: true

# Unpublished private preparation. Empty technical tables only: installation
# creates no queued work, hooks, jobs, grants, readiness or historical effects.
class CreateContactCenterEndingActionAttempts < ActiveRecord::Migration[7.1]
  ATTEMPTS = :jrc_contact_center_ending_action_attempts
  OUTCOMES = :jrc_contact_center_ending_action_attempt_outcomes
  SQL = 'db/functions/20261124001000_contact_center_ending_attempts.sql'
  SOURCES = {
    'db/functions/20261124001000_contact_center_ending_attempts.sql' => '7c317f8dde21ef093a5c6ebe12b09f5b84fc65d253f61d5a01256e3e88e1f29f',
    'lib/jrc_contact_center/ending_action_attempt_schema_receipt.rb' => 'd143e6d8b95c4af20047af63fb68fb8694492d6063f0a3ff2c14eb53ed0fdb6f'
  }.freeze

  def up
    load_sources!
    receipt = JrcContactCenter::EndingActionAttemptSchemaReceipt.new(connection)
    return receipt.verify! if table_exists?(ATTEMPTS) || table_exists?(OUTCOMES)

    create_attempts
    create_outcomes
    create_references
    create_constraints
    execute File.read(Rails.root.join(SQL))
    receipt.stamp!
    receipt.verify!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Attempt history requires a separately reviewed rollback'
  end

  private

  def load_sources!
    raise ActiveRecord::MigrationError, 'Unreviewed ending attempt candidate' unless SOURCES.keys.include?(SQL)

    SOURCES.each do |path, expected|
      raise ActiveRecord::MigrationError, 'Unreviewed ending attempt source; preserve history' unless
        Digest::SHA256.file(Rails.root.join(path)).hexdigest == expected
    end
    require Rails.root.join('lib/jrc_contact_center/ending_action_attempt_schema_receipt')
  end

  def create_attempts
    create_table ATTEMPTS do |table|
      table.bigint :account_id, :origin_id, :readiness_id, :version_id, :actor_account_user_id, :actor_user_id, null: false
      table.string :rule_code, null: false, limit: 100
      table.string :destination_kind, null: false, limit: 50
      table.uuid :request_key, null: false
      table.datetime :created_at, null: false
      table.string :integrity_sha256, null: false, limit: 64
    end
    add_index ATTEMPTS, [:account_id, :request_key], unique: true, name: 'cc_ending_attempt_request'
    add_index ATTEMPTS, [:id, :account_id], unique: true, name: 'cc_ending_attempt_account'
    add_index ATTEMPTS, [:account_id, :origin_id, :rule_code, :destination_kind], name: 'cc_ending_attempt_destination'
  end

  def create_outcomes
    create_table OUTCOMES do |table|
      table.bigint :account_id, :attempt_id, null: false
      table.bigint :execution_id
      table.string :outcome, :result_code, null: false, limit: 50
      table.datetime :created_at, null: false
      table.string :integrity_sha256, null: false, limit: 64
    end
    add_index OUTCOMES, [:account_id, :attempt_id], unique: true, name: 'cc_ending_attempt_one_outcome'
  end

  def create_references
    [ATTEMPTS, OUTCOMES].each do |table|
      add_foreign_key table, :jrc_contact_center_ending_scope_accounts, column: :account_id, primary_key: :account_id, on_delete: :cascade
    end
    add_reference_key(ATTEMPTS, :jrc_contact_center_ending_action_origins, :origin_id, 'cc_ending_attempt_origin_fk')
    add_reference_key(ATTEMPTS, :jrc_contact_center_ending_action_readinesses, :readiness_id, 'cc_ending_attempt_readiness_fk')
    add_reference_key(OUTCOMES, ATTEMPTS, :attempt_id, 'cc_ending_outcome_attempt_fk')
    add_reference_key(OUTCOMES, :jrc_contact_center_ending_action_executions, :execution_id, 'cc_ending_outcome_execution_fk')
  end

  def add_reference_key(table, target, column, name)
    add_foreign_key table, target, column: [column, :account_id], primary_key: [:id, :account_id], deferrable: :deferred, name: name
  end

  def create_constraints
    fields = %w[account_id origin_id readiness_id version_id actor_account_user_id actor_user_id]
    add_check_constraint ATTEMPTS, fields.map { |field| "#{field} > 0" }.join(' AND '), name: 'cc_ending_attempt_identity'
    add_check_constraint ATTEMPTS, "destination_kind::text = 'project_task'::text AND btrim(rule_code) <> ''", name: 'cc_ending_attempt_kind'
    add_check_constraint OUTCOMES, 'account_id > 0 AND attempt_id > 0', name: 'cc_ending_outcome_identity'
    add_check_constraint ATTEMPTS, "integrity_sha256 ~ '^[0-9a-f]{64}$'", name: 'cc_ending_attempt_digest'
    add_check_constraint OUTCOMES, "integrity_sha256 ~ '^[0-9a-f]{64}$'", name: 'cc_ending_outcome_digest'
    add_outcome_constraint
  end

  def add_outcome_constraint
    blocked = %w[authorization_denied reference_unavailable deactivated confirmation_required trigger_pending operation_unavailable]
    codes = "ARRAY[#{blocked.map { |code| "'#{code}'::text" }.join(',')}]"
    check = <<~SQL.squish
      (outcome::text = 'succeeded'::text AND result_code::text = 'completed'::text AND execution_id IS NOT NULL AND execution_id > 0)
      OR (outcome::text = 'blocked'::text AND result_code::text = ANY (#{codes}) AND execution_id IS NULL)
      OR (outcome::text = 'failed'::text AND result_code::text = 'destination_failure'::text AND execution_id IS NULL)
    SQL
    add_check_constraint OUTCOMES, check, name: 'cc_ending_outcome_result'
  end
end
