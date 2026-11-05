class CreateBackofficeSignatureArtifactBundles < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_backoffice_signature_artifact_bundles do |t|
      t.references :account, null: false, foreign_key: true
      t.references :delivery, null: false, index: { unique: true }, foreign_key: { to_table: :jrc_backoffice_signature_deliveries }
      t.references :contract_version, null: false, index: { unique: true }, foreign_key: { to_table: :jrc_backoffice_contract_versions }
      t.references :signed_document, null: false, foreign_key: { to_table: :jrc_backoffice_document_versions }
      t.references :certificate_document, null: false, foreign_key: { to_table: :jrc_backoffice_document_versions }
      t.references :captured_by, null: false, foreign_key: { to_table: :users }
      t.text :source_snapshot, null: false
      t.string :source_digest, null: false, limit: 64
      t.timestamps
    end
  end
end
