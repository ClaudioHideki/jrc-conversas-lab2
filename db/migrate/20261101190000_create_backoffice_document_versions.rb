class CreateBackofficeDocumentVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_backoffice_document_versions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :backoffice_request, null: false, foreign_key: { to_table: :jrc_crm_backoffice_requests }, index: false
      t.references :uploaded_by, null: false, foreign_key: { to_table: :users }
      t.string :document_key, null: false
      t.integer :version, null: false
      t.string :idempotency_key, null: false
      t.string :sha256, null: false
      t.timestamps
    end
    add_index :jrc_backoffice_document_versions, [:backoffice_request_id, :document_key, :version], unique: true,
              name: 'idx_backoffice_document_version'
    add_index :jrc_backoffice_document_versions, [:backoffice_request_id, :idempotency_key], unique: true,
              name: 'idx_backoffice_document_intent'
    add_check_constraint :jrc_backoffice_document_versions, 'version > 0', name: 'backoffice_document_positive_version'

    create_table :jrc_backoffice_document_analyses do |t|
      t.references :document_version, null: false, foreign_key: { to_table: :jrc_backoffice_document_versions }, index: false
      t.string :analyzer_version, null: false
      t.string :state, null: false
      t.jsonb :evidence, null: false, default: {}
      t.timestamps
    end
    add_index :jrc_backoffice_document_analyses, :document_version_id, unique: true, name: 'idx_backoffice_analysis_version'

    create_table :jrc_backoffice_document_decisions do |t|
      t.references :document_version, null: false, foreign_key: { to_table: :jrc_backoffice_document_versions }, index: false
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :status, null: false
      t.text :reason, null: false
      t.timestamps
    end
    add_index :jrc_backoffice_document_decisions, [:document_version_id, :id], name: 'idx_backoffice_decision_history'
  end
end
