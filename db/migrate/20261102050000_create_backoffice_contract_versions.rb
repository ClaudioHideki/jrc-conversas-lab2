class CreateBackofficeContractVersions < ActiveRecord::Migration[7.1]
  def up
    add_index :jrc_crm_contracts, %i[account_id id], unique: true, name: 'bo_contract_version_contract_tenant'
    add_index :jrc_crm_backoffice_requests, %i[account_id id], unique: true, name: 'bo_contract_version_request_tenant'
    create_versions
    index_versions
    pin_versions
  end

  def down
    if select_value('SELECT id FROM jrc_backoffice_contract_versions LIMIT 1')
      raise ActiveRecord::IrreversibleMigration, 'Preserve contract versions and their PDFs; an explicit archival plan is required'
    end

    drop_table :jrc_backoffice_contract_versions
    execute 'DROP FUNCTION jrc_contract_version_pin()'
    remove_index :jrc_crm_contracts, name: 'bo_contract_version_contract_tenant'
    remove_index :jrc_crm_backoffice_requests, name: 'bo_contract_version_request_tenant'
  end

  private

  def create_versions
    create_table :jrc_backoffice_contract_versions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :backoffice_request, null: false, foreign_key: { to_table: :jrc_crm_backoffice_requests }
      t.references :contract, null: false, foreign_key: { to_table: :jrc_crm_contracts }
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :pdf_blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.integer :number, null: false
      t.integer :source_format_version, null: false, default: 1
      t.string :idempotency_key, null: false
      t.string :source_digest, :pdf_sha256, null: false
      t.text :source_snapshot, :change_reason, null: false
      t.jsonb :change_paths, null: false, default: []
      t.timestamps
    end
  end

  def index_versions
    add_index :jrc_backoffice_contract_versions, %i[contract_id number], unique: true, name: 'bo_contract_version_number'
    add_index :jrc_backoffice_contract_versions, %i[contract_id idempotency_key], unique: true, name: 'bo_contract_version_intent'
    add_index :jrc_backoffice_contract_versions, %i[account_id id], unique: true, name: 'bo_contract_version_tenant'
    add_check_constraint :jrc_backoffice_contract_versions, 'number > 0 AND source_format_version > 0', name: 'bo_contract_version_positive'
    %i[contract backoffice_request].each do |reference|
      add_foreign_key :jrc_backoffice_contract_versions, "jrc_crm_#{reference == :contract ? 'contracts' : 'backoffice_requests'}",
                      column: [:account_id, :"#{reference}_id"], primary_key: %i[account_id id], name: "bo_version_#{reference}_tenant"
    end
  end

  def pin_versions
    execute <<~SQL.squish
      CREATE FUNCTION jrc_contract_version_pin() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'Contract versions are immutable';
      END;
      $$;
      CREATE TRIGGER jrc_contract_version_pin BEFORE UPDATE OR DELETE ON jrc_backoffice_contract_versions
      FOR EACH ROW EXECUTE FUNCTION jrc_contract_version_pin();
    SQL
  end
end
