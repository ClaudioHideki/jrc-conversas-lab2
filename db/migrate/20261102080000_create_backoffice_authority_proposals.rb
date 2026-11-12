class CreateBackofficeAuthorityProposals < ActiveRecord::Migration[7.1]
  def up
    add_index :jrc_backoffice_contract_versions, %i[account_id contract_id backoffice_request_id signer_roster_id id],
              unique: true, name: 'bo_contract_version_signing_origin'
    create_proposals
    add_fences
  end

  def down
    if select_value('SELECT id FROM jrc_backoffice_authority_proposals LIMIT 1')
      raise ActiveRecord::IrreversibleMigration, 'Preserve authority proposals, approvals and their exact contract versions'
    end

    drop_table :jrc_backoffice_authority_proposals
    remove_index :jrc_backoffice_contract_versions, name: 'bo_contract_version_signing_origin'
  end

  private

  def create_proposals
    create_table :jrc_backoffice_authority_proposals do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contract_version, null: false, foreign_key: { to_table: :jrc_backoffice_contract_versions }
      t.references :signer_roster, null: false, foreign_key: { to_table: :jrc_backoffice_signer_rosters }
      t.references :contract, null: false, foreign_key: { to_table: :jrc_crm_contracts }
      t.references :backoffice_request, null: false, foreign_key: { to_table: :jrc_crm_backoffice_requests }
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.integer :revision, null: false
      t.string :idempotency_key, :input_digest, :source_digest, null: false
      t.string :change_reason, null: false, limit: 2000
      t.text :source_snapshot, null: false
      t.timestamps
    end
  end

  def add_fences
    add_index :jrc_backoffice_authority_proposals, %i[account_id id], unique: true, name: 'bo_authority_proposal_tenant'
    add_index :jrc_backoffice_authority_proposals, %i[contract_version_id revision], unique: true, name: 'bo_authority_proposal_revision'
    add_index :jrc_backoffice_authority_proposals, %i[backoffice_request_id idempotency_key], unique: true, name: 'bo_authority_proposal_intent'
    add_foreign_key :jrc_backoffice_authority_proposals, :jrc_backoffice_contract_versions,
                    column: %i[account_id contract_id backoffice_request_id signer_roster_id contract_version_id],
                    primary_key: %i[account_id contract_id backoffice_request_id signer_roster_id id], name: 'bo_authority_exact_version_origin'
    add_check_constraint :jrc_backoffice_authority_proposals, 'revision > 0', name: 'bo_authority_proposal_positive'
    execute <<~SQL.squish
      CREATE TRIGGER jrc_authority_proposal_pin BEFORE UPDATE OR DELETE ON jrc_backoffice_authority_proposals
      FOR EACH ROW EXECUTE FUNCTION jrc_contract_version_pin();
    SQL
  end
end
