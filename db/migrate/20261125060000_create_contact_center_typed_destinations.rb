# frozen_string_literal: true

require 'digest'

# Additive, empty technical history only. Installation does not grant access,
# activate rules, backfill calls, enqueue work or invoke a native destination.
class CreateContactCenterTypedDestinations < ActiveRecord::Migration[7.1]
  CONSENTS = :jrc_contact_center_ending_destination_consents
  ATTEMPTS = :jrc_contact_center_ending_destination_attempts
  EXECUTIONS = :jrc_contact_center_ending_destination_executions
  OUTCOMES = :jrc_contact_center_ending_destination_outcomes
  TABLES = [CONSENTS, ATTEMPTS, EXECUTIONS, OUTCOMES].freeze
  SQL = 'db/functions/20261125060000_contact_center_typed_destinations.sql'
  RECEIPT = 'lib/jrc_contact_center/ending_destination_schema_receipt.rb'
  SOURCES = {
    SQL => '2a1512a700604017b5f62b05d02e7152eb4335e61785775e041ba5bcca142940',
    RECEIPT => 'c9a18646d496cc2ec06605dfaaa81290ad5ea030419dc10fe170d00015899f7b'
  }.freeze

  def up
    load_sources!
    receipt = JrcContactCenter::EndingDestinationSchemaReceipt.new(connection)
    return receipt.verify! if TABLES.any? { |table| table_exists?(table) }

    create_tables
    create_indexes
    create_references
    create_constraints
    execute File.read(Rails.root.join(SQL))
    receipt.stamp!
    receipt.verify!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Typed ending history requires a separately reviewed rollback'
  end

  private

  def load_sources!
    SOURCES.each do |path, expected|
      raise ActiveRecord::MigrationError, 'Unreviewed typed ending history source; preserve existing schema' unless
        Digest::SHA256.file(Rails.root.join(path)).hexdigest == expected
    end
    require Rails.root.join(RECEIPT.delete_suffix('.rb'))
  end

  def identity_table(name)
    create_table name do |table|
      table.bigint :account_id, :origin_id, :readiness_id, :version_id, :actor_account_user_id, :actor_user_id, null: false
      table.string :rule_code, null: false, limit: 100
      table.string :destination_kind, :operation, :trigger_kind, null: false, limit: 50
      table.string :rule_sha256, :integrity_sha256, null: false, limit: 64
      table.bigint :trigger_id, null: false
      table.datetime :triggered_at, null: false
      table.datetime :created_at, null: false
      yield table
    end
  end

  def create_tables
    identity_table(CONSENTS) { |table| table.uuid :request_key, null: false }
    identity_table(ATTEMPTS) do |table|
      table.bigint :consent_id, :retry_of_id, :retry_requested_by_account_user_id
      table.uuid :request_key, :effect_key, null: false
    end
    identity_table(EXECUTIONS) do |table|
      table.bigint :attempt_id, :target_id, null: false
      table.uuid :request_key, :effect_key, null: false
      table.string :target_type, null: false, limit: 100
      table.bigint :native_audit_id, :native_version
    end
    create_table OUTCOMES do |table|
      table.bigint :account_id, :attempt_id, null: false
      table.bigint :execution_id
      table.string :outcome, :result_code, null: false, limit: 50
      table.datetime :created_at, null: false
      table.string :integrity_sha256, null: false, limit: 64
    end
  end

  def create_indexes
    { CONSENTS => 'consent', ATTEMPTS => 'attempt', EXECUTIONS => 'execution' }.each do |table, name|
      add_index table, %i[id account_id], unique: true, name: "cc_typed_#{name}_account"
    end
    add_index CONSENTS, %i[account_id request_key], unique: true, name: 'cc_typed_consent_request'
    add_index ATTEMPTS, %i[account_id request_key], unique: true, name: 'cc_typed_attempt_request'
    add_index ATTEMPTS, %i[account_id origin_id rule_code destination_kind], unique: true,
                                                                             where: 'retry_of_id IS NULL', name: 'cc_typed_one_root_attempt'
    add_index ATTEMPTS, %i[account_id retry_of_id], unique: true, where: 'retry_of_id IS NOT NULL', name: 'cc_typed_one_retry_child'
    add_index ATTEMPTS, %i[account_id consent_id], unique: true, where: 'consent_id IS NOT NULL', name: 'cc_typed_consent_used_once'
    add_index ATTEMPTS, %i[account_id origin_id rule_code destination_kind id], name: 'cc_typed_attempt_history'
    add_index EXECUTIONS, %i[account_id attempt_id], unique: true, name: 'cc_typed_execution_attempt'
    add_index EXECUTIONS, %i[account_id origin_id rule_code destination_kind], unique: true, name: 'cc_typed_one_native_success'
    add_index OUTCOMES, %i[account_id attempt_id], unique: true, name: 'cc_typed_one_outcome'
  end

  def create_references
    TABLES.each do |table|
      add_foreign_key table, :jrc_contact_center_ending_scope_accounts,
                      column: :account_id, primary_key: :account_id, on_delete: :cascade
    end
    reference_key(CONSENTS, :jrc_contact_center_ending_action_origins, :origin_id, 'cc_typed_consent_origin_fk')
    reference_key(CONSENTS, :jrc_contact_center_ending_action_readinesses, :readiness_id, 'cc_typed_consent_ready_fk')
    reference_key(ATTEMPTS, :jrc_contact_center_ending_action_origins, :origin_id, 'cc_typed_attempt_origin_fk')
    reference_key(ATTEMPTS, :jrc_contact_center_ending_action_readinesses, :readiness_id, 'cc_typed_attempt_ready_fk')
    reference_key(ATTEMPTS, CONSENTS, :consent_id, 'cc_typed_attempt_consent_fk')
    reference_key(ATTEMPTS, ATTEMPTS, :retry_of_id, 'cc_typed_attempt_retry_fk')
    reference_key(EXECUTIONS, ATTEMPTS, :attempt_id, 'cc_typed_execution_attempt_fk')
    reference_key(OUTCOMES, ATTEMPTS, :attempt_id, 'cc_typed_outcome_attempt_fk')
    reference_key(OUTCOMES, EXECUTIONS, :execution_id, 'cc_typed_outcome_execution_fk')
  end

  def reference_key(table, target, column, name)
    add_foreign_key table, target, column: [column, :account_id], primary_key: %i[id account_id], deferrable: :deferred, name: name
  end

  def create_constraints
    { CONSENTS => 'consent', ATTEMPTS => 'attempt', EXECUTIONS => 'execution' }.each do |table, name|
      identity_constraints(table, name)
    end
    add_check_constraint ATTEMPTS, '(retry_of_id IS NULL) = (retry_requested_by_account_user_id IS NULL)', name: 'cc_typed_retry_actor'
    add_check_constraint ATTEMPTS, '(consent_id IS NULL OR consent_id > 0) AND (retry_of_id IS NULL OR retry_of_id > 0) AND ' \
                                   '(retry_requested_by_account_user_id IS NULL OR retry_requested_by_account_user_id > 0)',
                         name: 'cc_typed_attempt_optional_refs'
    add_check_constraint EXECUTIONS, 'attempt_id > 0 AND target_id > 0 AND (native_audit_id IS NULL OR native_audit_id > 0)',
                         name: 'cc_typed_execution_target'
    add_check_constraint EXECUTIONS, "(destination_kind = 'service_desk' AND native_version IS NOT NULL AND native_version >= 0) OR " \
                                     "(destination_kind <> 'service_desk' AND native_version IS NULL)", name: 'cc_typed_execution_version'
    add_check_constraint OUTCOMES, 'account_id > 0 AND attempt_id > 0', name: 'cc_typed_outcome_identity'
    add_check_constraint OUTCOMES, "integrity_sha256 ~ '^[0-9a-f]{64}$'", name: 'cc_typed_outcome_digest'
    execution_type_constraint
    outcome_constraint
  end

  def execution_type_constraint
    check = <<~SQL.squish
      (operation = 'create_task' AND target_type = 'JrcProjects::Task') OR
      (operation = 'create_lead' AND target_type = 'JrcCrm::Lead') OR
      (operation = 'create_activity' AND target_type = 'JrcCrm::Activity') OR
      (operation IN ('create_ticket','update_ticket') AND target_type = 'JrcServiceDesk::Ticket')
    SQL
    add_check_constraint EXECUTIONS, check, name: 'cc_typed_execution_type'
  end

  def identity_constraints(table, name)
    fields = %w[account_id origin_id readiness_id version_id actor_account_user_id actor_user_id trigger_id]
    add_check_constraint table, fields.map { |field| "#{field} > 0" }.join(' AND '), name: "cc_typed_#{name}_identity"
    add_check_constraint table, "rule_sha256 ~ '^[0-9a-f]{64}$' AND integrity_sha256 ~ '^[0-9a-f]{64}$'", name: "cc_typed_#{name}_digests"
    add_check_constraint table, "btrim(rule_code) <> '' AND trigger_kind IN ('ending_reason_confirmation','ending_action_completion')",
                         name: "cc_typed_#{name}_trigger"
    add_check_constraint table, 'created_at >= triggered_at', name: "cc_typed_#{name}_clock"
    allowed = <<~SQL.squish
      (destination_kind = 'project_task' AND operation = 'create_task') OR
      (destination_kind = 'crm' AND operation IN ('create_lead','create_activity')) OR
      (destination_kind = 'service_desk' AND operation IN ('create_ticket','update_ticket'))
    SQL
    add_check_constraint table, allowed, name: "cc_typed_#{name}_operation"
  end

  def outcome_constraint
    blocked = %w[authorization_denied reference_unavailable deactivated confirmation_required trigger_pending operation_unavailable]
    codes = "ARRAY[#{blocked.map { |code| "'#{code}'::text" }.join(',')}]"
    check = <<~SQL.squish
      (outcome = 'succeeded' AND result_code = 'completed' AND execution_id IS NOT NULL AND execution_id > 0)
      OR (outcome = 'blocked' AND result_code = ANY (#{codes}) AND execution_id IS NULL)
      OR (outcome = 'failed' AND result_code = 'destination_failure' AND execution_id IS NULL)
    SQL
    add_check_constraint OUTCOMES, check, name: 'cc_typed_outcome_result'
  end
end
