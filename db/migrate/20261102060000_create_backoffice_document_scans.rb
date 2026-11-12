class CreateBackofficeDocumentScans < ActiveRecord::Migration[7.1]
  def up
    add_index :jrc_backoffice_document_versions, %i[account_id id], unique: true, name: 'bo_document_version_tenant'
    create_observations
    constrain_observations
    execute Rails.root.join('db/functions/20261102060000_backoffice_document_guards.sql').read
  end

  def down
    if select_value('SELECT id FROM jrc_backoffice_document_scans LIMIT 1')
      raise ActiveRecord::IrreversibleMigration, 'Preserve document security observations; archive them explicitly before rollback'
    end

    execute 'DROP TRIGGER jrc_bo_private_attachment ON active_storage_attachments'
    execute 'DROP FUNCTION jrc_bo_private_attachment()'
    execute 'DROP TRIGGER jrc_bo_document_version_pin ON jrc_backoffice_document_versions'
    remove_foreign_key :jrc_backoffice_document_versions, name: 'bo_document_request_tenant'
    drop_table :jrc_backoffice_document_scans
    execute 'DROP FUNCTION jrc_bo_document_scan_pin()'
    remove_index :jrc_backoffice_document_versions, name: 'bo_document_version_tenant'
  end

  private

  def create_observations
    create_table :jrc_backoffice_document_scans do |t|
      t.references :account, null: false, foreign_key: true
      t.references :document_version, null: false, foreign_key: { to_table: :jrc_backoffice_document_versions }
      t.references :source_blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.integer :attempt, null: false
      t.string :state, :expected_sha256, :scanner_adapter, null: false
      t.string :observed_sha256, :failure_code
      t.timestamps
    end
  end

  def constrain_observations
    add_foreign_key :jrc_backoffice_document_versions, :jrc_crm_backoffice_requests,
                    column: %i[account_id backoffice_request_id], primary_key: %i[account_id id], name: 'bo_document_request_tenant'
    add_index :jrc_backoffice_document_scans, %i[document_version_id attempt], unique: true, name: 'bo_document_scan_attempt'
    add_foreign_key :jrc_backoffice_document_scans, :jrc_backoffice_document_versions,
                    column: %i[account_id document_version_id], primary_key: %i[account_id id], name: 'bo_document_scan_tenant'
    add_check_constraint :jrc_backoffice_document_scans,
                         "attempt > 0 AND state IN ('clean','infected','unavailable','checksum_mismatch')", name: 'bo_document_scan_state'
    add_check_constraint :jrc_backoffice_document_scans,
                         "state <> 'clean' OR (observed_sha256 IS NOT NULL AND observed_sha256 = expected_sha256)", name: 'bo_document_scan_clean'
  end
end
