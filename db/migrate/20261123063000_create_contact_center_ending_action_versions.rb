# frozen_string_literal: true

# Unapplied WIP. No public route or execution trigger is introduced by this migration.
class CreateContactCenterEndingActionVersions < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_ending_action_versions
  SQL = 'db/functions/20261123063000_contact_center_ending_action_versions.sql'
  SOURCES = {
    SQL => '0d8c92f02f01f49f3a783bc468bfd20e1e37fc86bfca6b2409cea69bec12c253',
    'lib/jrc_contact_center/ending_action_version_schema_receipt.rb' => '1ba3e81f7d75c59c7ac8133b8dd119388e42129e77f9ef00ab1cf28df3d9b24c'
  }.freeze

  def up
    load_sources!
    receipt = JrcContactCenter::EndingActionVersionSchemaReceipt.new(connection)
    return receipt.verify! if table_exists?(TABLE)

    reject_unproven_configuration!
    create_records
    indexes
    constraints
    execute File.read(Rails.root.join(SQL))
    receipt.stamp!
    receipt.verify!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Ending action version history requires a separately reviewed rollback'
  end

  private

  def load_sources!
    SOURCES.each do |path, expected|
      raise ActiveRecord::MigrationError, 'Ending action version source changed; preserve history' unless
        Digest::SHA256.file(Rails.root.join(path)).hexdigest == expected
    end
    require Rails.root.join('lib/jrc_contact_center/ending_action_version_schema_receipt')
  end

  # A pre-existing head cannot prove a private template or its actor/effective time.
  # No definition is reconstructed from account settings or an older audit.
  def reject_unproven_configuration!
    exists = connection.select_value(<<~SQL.squish)
      SELECT EXISTS (SELECT 1 FROM accounts WHERE
      (settings -> 'jrc_contact_center_acw') ? 'voice_ending_automations')
    SQL
    raise ActiveRecord::MigrationError, 'Unproven ending action configuration; preserve source and investigate' if exists
  end

  def create_records
    create_table TABLE do |table|
      table.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      table.integer :revision, null: false
      table.bigint :source_audit_id, :actor_user_id, null: false
      table.string :actor_user_type, null: false
      table.uuid :head_nonce, null: false
      table.jsonb :private_definition, null: false
      table.string :definition_sha256, :integrity_sha256, null: false, limit: 64
      table.datetime :created_at, null: false
    end
  end

  def indexes
    add_index TABLE, [:account_id, :revision], unique: true, name: 'cc_ending_action_version_revision'
    add_index TABLE, [:id, :account_id], unique: true, name: 'cc_ending_action_version_account'
    add_index TABLE, :source_audit_id, unique: true, name: 'cc_ending_action_version_audit'
    add_index TABLE, [:account_id, :head_nonce], unique: true, name: 'cc_ending_action_version_head'
    add_index TABLE, [:account_id, :created_at], name: 'cc_ending_action_version_effective'
  end

  def constraints
    identity = "revision > 0 AND actor_user_id > 0 AND actor_user_type = 'User' AND " \
               "head_nonce::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'"
    add_check_constraint TABLE, identity, name: 'cc_ending_action_version_identity'
    hashes = "definition_sha256 ~ '^[0-9a-f]{64}$' AND integrity_sha256 ~ '^[0-9a-f]{64}$'"
    add_check_constraint TABLE, hashes, name: 'cc_ending_action_version_hashes'
    # Wire definitions are bounded at256KiB; PostgreSQL's normalized JSON adds whitespace.
    document = "jsonb_typeof(private_definition) = 'object' AND octet_length(private_definition::text) <= 524288 " \
               "AND jsonb_typeof(private_definition -> 'version') = 'number' " \
               "AND (private_definition ->> 'version')::integer = revision " \
               "AND jsonb_typeof(private_definition -> 'entries') = 'array' " \
               "AND jsonb_array_length(private_definition -> 'entries') <= 100"
    add_check_constraint TABLE, document, name: 'cc_ending_action_version_definition'
  end
end
