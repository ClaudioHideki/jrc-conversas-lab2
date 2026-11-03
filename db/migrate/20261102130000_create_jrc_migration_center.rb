class CreateJrcMigrationCenter < ActiveRecord::Migration[7.1]
  def change
    create_batches
    create_items
    create_mappings
  end

  private

  # Keep the table's declarative columns together for schema review.
  def create_batches
    create_table :jrc_migration_batches do |t|
      t.references :account, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :accepted_by, foreign_key: { to_table: :users }
      t.string :source, null: false
      t.string :domain, null: false
      t.string :status, null: false, default: 'staged'
      t.integer :version, null: false, default: 1
      t.jsonb :field_mapping, null: false, default: {}
      t.string :source_digest, null: false
      t.string :file_name
      t.jsonb :summary, null: false, default: {}
      t.jsonb :reconciliation, null: false, default: {}
      t.datetime :executed_at
      t.datetime :accepted_at
      t.text :acceptance_note
      t.timestamps
    end
    add_index :jrc_migration_batches, [:account_id, :id], unique: true
  end

  def create_items
    create_table :jrc_migration_items do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :batch_id, null: false
      t.string :legacy_id, null: false
      t.jsonb :raw_data, null: false
      t.jsonb :normalized_data, null: false, default: {}
      t.string :source_digest, null: false
      t.string :decision
      t.string :status, null: false, default: 'staged'
      t.string :error_code
      t.jsonb :validation_errors, null: false, default: []
      t.bigint :target_id
      t.string :target_digest
      t.jsonb :before_data, null: false, default: {}
      t.datetime :migrated_at
      t.timestamps
    end
    add_index :jrc_migration_items, [:batch_id, :legacy_id], unique: true
    add_foreign_key :jrc_migration_items, :jrc_migration_batches, column: [:account_id, :batch_id], primary_key: [:account_id, :id]
  end

  def create_mappings
    create_table :jrc_migration_mappings do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :batch_id, null: false
      t.string :source, null: false
      t.string :domain, null: false
      t.string :legacy_id, null: false
      t.bigint :target_id, null: false
      t.string :source_digest, null: false
      t.string :target_digest, null: false
      t.datetime :source_updated_at, null: false
      t.datetime :accepted_at
      t.references :accepted_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :jrc_migration_mappings, [:account_id, :source, :domain, :legacy_id], unique: true, name: 'jrc_migration_source_identity'
    add_index :jrc_migration_mappings, [:account_id, :domain, :target_id], name: 'jrc_migration_target'
    add_foreign_key :jrc_migration_mappings, :jrc_migration_batches, column: [:account_id, :batch_id], primary_key: [:account_id, :id]
  end
end
