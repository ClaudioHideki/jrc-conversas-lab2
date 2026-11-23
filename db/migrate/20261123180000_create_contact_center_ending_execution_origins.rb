# frozen_string_literal: true

# PRIVATE UNAPPLIED. Hash pins must be reviewed before transporting this complete
# increment to source. Installation creates empty evidence, never arms a rule.
class CreateContactCenterEndingExecutionOrigins < ActiveRecord::Migration[7.1]
  ORIGINS = :jrc_contact_center_ending_action_origins
  COMPLETIONS = :jrc_contact_center_ending_action_completions
  LEGS = :jrc_contact_center_call_legs
  SQL = 'db/functions/20261123180000_contact_center_ending_execution_origins.sql'
  SOURCES = {
    SQL => 'e9e97c3db666a8b5a59ae4852786a342b1df8101105b8b9ce1415d71e5cf1ed6',
    'lib/jrc_contact_center/ending_execution_origin_schema_receipt.rb' => '4ce75de6aae5a1446ad30f52a7a7285286c8a636b76bee20a99e17006fac3587'
  }.freeze

  def up
    load_sources!
    receipt = JrcContactCenter::EndingExecutionOriginSchemaReceipt.new(connection)
    return receipt.verify! if table_exists?(ORIGINS) || table_exists?(COMPLETIONS) || column_exists?(LEGS, :ending_action_scope_version_id)

    create_leg_reference
    create_origins
    create_completions
    create_indexes
    create_references
    create_constraints
    execute File.read(Rails.root.join(SQL))
    receipt.stamp!
    receipt.verify!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Ending execution original evidence requires a separately reviewed rollback'
  end

  private

  def load_sources!
    SOURCES.each do |path, expected|
      raise ActiveRecord::MigrationError, 'Unreviewed ending execution origin source; preserve history' unless
        Digest::SHA256.file(Rails.root.join(path)).hexdigest == expected
    end
    require Rails.root.join('lib/jrc_contact_center/ending_execution_origin_schema_receipt')
  end

  def create_leg_reference
    add_column LEGS, :ending_action_scope_version_id, :bigint
    add_column LEGS, :ending_action_captured_started_at, :datetime
    pair = '(ending_action_scope_version_id IS NULL AND ending_action_captured_started_at IS NULL) OR ' \
           '(ending_action_scope_version_id IS NOT NULL AND ending_action_captured_started_at IS NOT NULL)'
    add_check_constraint LEGS, pair, name: 'cc_ending_execution_leg_capture'
    add_foreign_key LEGS, :jrc_contact_center_ending_action_queue_scopes,
                    column: [:ending_action_scope_version_id, :account_id], primary_key: [:id, :account_id],
                    deferrable: :deferred, name: 'cc_ending_execution_leg_scope_fk'
    add_index LEGS, :ending_action_scope_version_id, name: 'cc_ending_execution_leg_scope'
  end

  def create_origins
    create_table ORIGINS do |table|
      table.references :account, null: false, index: false
      table.bigint :qualification_id
      table.bigint :source_qualification_id, :origin_event_id, :call_session_id, :call_leg_id, null: false
      table.bigint :actor_account_user_id, :actor_user_id, :version_id, :ending_reason_catalog_id, null: false
      table.bigint :queue_scope_version_id, :queue_id, :unit_id, :issuer_company_id, null: false
      table.bigint :business_unit_id
      table.string :integrity_sha256, null: false, limit: 64
      table.jsonb :private_origin_evidence, null: false, default: {}
      table.datetime :created_at, null: false
    end
  end

  def create_completions
    create_table COMPLETIONS do |table|
      table.references :account, null: false, index: false
      table.bigint :origin_id, :source_qualification_id, null: false
      table.string :reason_code, :outcome_code, null: false, limit: 100
      table.string :integrity_sha256, null: false, limit: 64
      table.jsonb :private_completion_evidence, null: false, default: {}
      table.datetime :completed_at, null: false
      table.datetime :created_at, null: false
    end
  end

  def create_indexes
    add_index ORIGINS, [:account_id, :source_qualification_id], unique: true, name: 'cc_ending_execution_origin_source'
    add_index ORIGINS, [:account_id, :origin_event_id], unique: true, name: 'cc_ending_execution_origin_event'
    add_index ORIGINS, [:id, :account_id], unique: true, name: 'cc_ending_execution_origin_account'
    add_index ORIGINS, :qualification_id, unique: true, where: 'qualification_id IS NOT NULL', name: 'cc_ending_execution_origin_live'
    add_index COMPLETIONS, [:account_id, :origin_id], unique: true, name: 'cc_ending_execution_completion_origin'
  end

  def create_references
    [ORIGINS, COMPLETIONS].each do |table|
      add_foreign_key table, :jrc_contact_center_ending_scope_accounts, column: :account_id, primary_key: :account_id, on_delete: :cascade
    end
    add_foreign_key ORIGINS, :jrc_contact_center_qualifications, column: :qualification_id, on_delete: :nullify
    add_foreign_key ORIGINS, :jrc_contact_center_ending_action_versions,
                    column: [:version_id, :account_id],
                    primary_key: [:id, :account_id], deferrable: :deferred, name: 'cc_ending_execution_origin_version_fk'
    add_foreign_key ORIGINS, :jrc_contact_center_ending_action_queue_scopes,
                    column: [:queue_scope_version_id, :account_id],
                    primary_key: [:id, :account_id], deferrable: :deferred, name: 'cc_ending_execution_origin_scope_fk'
    add_foreign_key COMPLETIONS, ORIGINS,
                    column: [:origin_id, :account_id], primary_key: [:id, :account_id],
                    deferrable: :deferred, on_delete: :cascade, name: 'cc_ending_execution_completion_origin_fk'
  end

  def create_constraints
    keys = %w[source_qualification_id origin_event_id call_session_id call_leg_id actor_account_user_id actor_user_id version_id
              ending_reason_catalog_id queue_scope_version_id queue_id unit_id issuer_company_id]
    identity = keys.map { |name| "#{name} > 0" }.join(' AND ')
    identity += ' AND (business_unit_id IS NULL OR business_unit_id > 0) AND (qualification_id IS NULL OR qualification_id = source_qualification_id)'
    add_check_constraint ORIGINS, identity, name: 'cc_ending_execution_origin_identity'
    add_check_constraint COMPLETIONS, 'origin_id > 0 AND source_qualification_id > 0', name: 'cc_ending_execution_completion_identity'
    [ORIGINS, COMPLETIONS].each do |table|
      add_check_constraint table, "integrity_sha256 ~ '^[0-9a-f]{64}$'", name: "#{table}_digest"
    end
    add_check_constraint ORIGINS, bounded_evidence('private_origin_evidence'), name: 'cc_ending_execution_origin_evidence'
    add_check_constraint COMPLETIONS, bounded_evidence('private_completion_evidence'), name: 'cc_ending_execution_completion_evidence'
    add_check_constraint COMPLETIONS, "btrim(reason_code) <> '' AND btrim(outcome_code) <> ''", name: 'cc_ending_execution_completion_reason'
  end

  def bounded_evidence(column)
    "jsonb_typeof(#{column}) = 'object' AND octet_length(#{column}::text) <= 16384"
  end
end
