# frozen_string_literal: true

# Forward-only evidence, not rule activation. Existing calls, catalogues and authority are untouched.
class CreateContactCenterEndingActionScopes < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_ending_action_queue_scopes
  ACCOUNT_TABLE = :jrc_contact_center_ending_scope_accounts
  SQL = 'db/functions/20261123034500_contact_center_ending_action_scopes.sql'
  SOURCES = {
    SQL => '3f1ecc42e7944d40ddd838eb066dc1610a95465f27f614b11f692f9d1ee7fdd5',
    'lib/jrc_contact_center/ending_action_scope_schema_receipt.rb' => 'd23faa6189bae4c4ca93084e8c085f7839caa5f8383a8b6deb8fa248fdb68bb1'
  }.freeze

  def up
    load_sources!
    receipt = JrcContactCenter::EndingActionScopeSchemaReceipt.new(connection)
    return receipt.verify! if table_exists?(TABLE) || table_exists?(ACCOUNT_TABLE)

    create_account_references
    create_records
    indexes
    constraints
    execute File.read(Rails.root.join(SQL))
    execute "INSERT INTO #{ACCOUNT_TABLE}(account_id) SELECT id FROM accounts ORDER BY id"
    execute 'SELECT cc_ending_action_capture_queue_scope(id) FROM jrc_contact_center_queues ORDER BY account_id, id'
    receipt.stamp!
    receipt.verify!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Ending action scope history requires a separately reviewed rollback'
  end

  private

  def load_sources!
    SOURCES.each do |path, expected|
      raise ActiveRecord::MigrationError, 'Ending action scope source changed; preserve history' unless
        Digest::SHA256.file(Rails.root.join(path)).hexdigest == expected
    end
    require Rails.root.join('lib/jrc_contact_center/ending_action_scope_schema_receipt')
  end

  def create_records
    create_table TABLE do |table|
      table.references :account, null: false, index: false
      table.bigint :queue_id
      table.bigint :source_queue_id, :unit_id, null: false
      table.integer :revision, null: false
      table.bigint :issuer_company_id, :business_unit_id
      table.string :scope_state, null: false, limit: 16
      table.string :scope_digest, :integrity_sha256, null: false, limit: 64
      table.jsonb :payload, null: false, default: {}
      table.datetime :created_at, null: false
    end
  end

  # One immutable technical FK target per real Account, never a customer/provider registry.
  # Appending evidence must not retain a late KEY SHARE lock on the native authority row.
  def create_account_references
    create_table ACCOUNT_TABLE, id: false do |table|
      table.bigint :account_id, null: false, primary_key: true, default: nil
    end
    add_foreign_key ACCOUNT_TABLE, :accounts, column: :account_id, on_delete: :cascade
  end

  def indexes
    add_index TABLE, [:account_id, :source_queue_id, :revision], unique: true, name: 'cc_ending_action_scope_revision'
    add_index TABLE, [:account_id, :source_queue_id, :created_at], name: 'cc_ending_action_scope_effective'
    add_index TABLE, [:id, :account_id], unique: true, name: 'cc_ending_action_scope_account'
    add_index TABLE, :queue_id, name: 'cc_ending_action_scope_live_queue'
    add_foreign_key TABLE, :jrc_contact_center_queues, column: :queue_id, on_delete: :nullify
    add_foreign_key TABLE, ACCOUNT_TABLE, column: :account_id, primary_key: :account_id, on_delete: :cascade
  end

  def constraints
    identity = 'source_queue_id > 0 AND unit_id > 0 AND revision > 0 AND (queue_id IS NULL OR queue_id = source_queue_id)'
    add_check_constraint TABLE, identity, name: 'cc_ending_action_scope_identity'
    digests = "scope_digest ~ '^[0-9a-f]{64}$' AND integrity_sha256 ~ '^[0-9a-f]{64}$'"
    add_check_constraint TABLE, digests, name: 'cc_ending_action_scope_digests'
    state = "scope_state::text = ANY (ARRAY['mapped'::text, 'unmapped'::text, 'invalid'::text]) " \
            'AND (issuer_company_id IS NULL OR issuer_company_id > 0) AND (business_unit_id IS NULL OR business_unit_id > 0) ' \
            "AND (scope_state <> 'mapped' OR issuer_company_id IS NOT NULL)"
    add_check_constraint TABLE, state, name: 'cc_ending_action_scope_state'
    add_check_constraint TABLE, "jsonb_typeof(payload) = 'object' AND octet_length(payload::text) <= 8192", name: 'cc_ending_action_scope_payload'
  end
end
