class CreateBackofficeSignerRosters < ActiveRecord::Migration[7.1]
  def up
    create_table :jrc_backoffice_signer_rosters do |t|
      t.references :account, :contract, :backoffice_request, :created_by, null: false, index: true
      t.integer :revision, null: false
      t.string :customer_mode, :issuer_mode, :idempotency_key, :source_digest, :input_digest, null: false
      t.string :change_reason, limit: 2000, null: false
      t.text :source_snapshot, null: false
      t.timestamps
    end
    add_index :jrc_backoffice_signer_rosters, %i[backoffice_request_id contract_id revision], unique: true, name: 'bo_signer_roster_revision'
    add_index :jrc_backoffice_signer_rosters, %i[backoffice_request_id idempotency_key], unique: true, name: 'bo_signer_roster_intent'
    add_index :jrc_backoffice_signer_rosters, %i[account_id contract_id backoffice_request_id id], unique: true, name: 'bo_signer_roster_origin'
    constrain_rosters
    bind_versions
    execute <<~SQL.squish
      CREATE TRIGGER jrc_signer_roster_pin BEFORE UPDATE OR DELETE ON jrc_backoffice_signer_rosters
      FOR EACH ROW EXECUTE FUNCTION jrc_contract_version_pin();
    SQL
  end

  def down
    if select_value('SELECT id FROM jrc_backoffice_signer_rosters LIMIT 1')
      raise ActiveRecord::IrreversibleMigration, 'Preserve signer rosters and their exact contract versions'
    end

    remove_foreign_key :jrc_backoffice_contract_versions, name: 'bo_version_signer_roster_origin'
    remove_reference :jrc_backoffice_contract_versions, :signer_roster, foreign_key: { to_table: :jrc_backoffice_signer_rosters }
    drop_table :jrc_backoffice_signer_rosters
  end

  private

  def bind_versions
    add_reference :jrc_backoffice_contract_versions, :signer_roster, foreign_key: { to_table: :jrc_backoffice_signer_rosters }
    add_foreign_key :jrc_backoffice_contract_versions, :jrc_backoffice_signer_rosters,
                    column: %i[account_id contract_id backoffice_request_id signer_roster_id],
                    primary_key: %i[account_id contract_id backoffice_request_id id], name: 'bo_version_signer_roster_origin'
  end

  def constrain_rosters
    add_foreign_key :jrc_backoffice_signer_rosters, :accounts
    add_foreign_key :jrc_backoffice_signer_rosters, :users, column: :created_by_id
    add_foreign_key :jrc_backoffice_signer_rosters, :jrc_crm_contracts, column: :contract_id
    add_foreign_key :jrc_backoffice_signer_rosters, :jrc_crm_backoffice_requests, column: :backoffice_request_id
    add_foreign_key :jrc_backoffice_signer_rosters, :jrc_crm_contracts, column: %i[account_id contract_id],
                                                                        primary_key: %i[account_id id], name: 'bo_signer_roster_contract_tenant'
    add_foreign_key :jrc_backoffice_signer_rosters, :jrc_crm_backoffice_requests,
                    column: %i[account_id backoffice_request_id], primary_key: %i[account_id id], name: 'bo_signer_roster_request_tenant'
    add_check_constraint :jrc_backoffice_signer_rosters,
                         "revision > 0 AND customer_mode IN ('single','joint') AND issuer_mode IN ('single','joint')",
                         name: 'bo_signer_roster_modes'
  end
end
