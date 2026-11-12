class CreateBackofficeSignatureAcceptances < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_backoffice_signature_acceptances do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contract, null: false, index: { unique: true }, foreign_key: { to_table: :jrc_crm_contracts }
      t.references :bundle, null: false, index: { unique: true }, foreign_key: { to_table: :jrc_backoffice_signature_artifact_bundles }
      t.references :signed_blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.references :accepted_by, null: false, foreign_key: { to_table: :users }
      t.text :source_snapshot, null: false
      t.string :source_digest, null: false, limit: 64
      t.timestamps
    end
  end
end
