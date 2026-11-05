class CreateBackofficeCompletionDossiers < ActiveRecord::Migration[7.1]
  def up
    create_table :jrc_backoffice_completion_dossiers do |t|
      t.references :account, null: false, foreign_key: true
      t.references :backoffice_request, null: false, foreign_key: { to_table: :jrc_crm_backoffice_requests }
      t.references :archive_blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.references :sealed_by, null: false, foreign_key: { to_table: :users }
      t.integer :number, null: false
      t.text :source_snapshot, null: false
      t.string :source_digest, :manifest_digest, :archive_sha256, null: false, limit: 64
      t.timestamps
    end
    add_index :jrc_backoffice_completion_dossiers, %i[backoffice_request_id number], unique: true, name: 'bo_dossier_number'
    add_index :jrc_backoffice_completion_dossiers, %i[backoffice_request_id manifest_digest], unique: true, name: 'bo_dossier_manifest'
    execute Rails.root.join('db/functions/20261105130000_backoffice_dossier_guards.sql').read
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Preserve sealed documentary dossiers and private archives'
  end
end
