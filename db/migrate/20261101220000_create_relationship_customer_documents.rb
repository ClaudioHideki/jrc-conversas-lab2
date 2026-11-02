class CreateRelationshipCustomerDocuments < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_relationship_customer_documents do |t|
      t.references :account, null: false, foreign_key: true
      t.references :assignment, null: false, foreign_key: { to_table: :jrc_relationship_assignments }
      t.string :title, null: false
      t.string :category, null: false, default: 'other'
      t.string :status, null: false, default: 'active'
      t.timestamps
    end
    add_index :jrc_relationship_customer_documents, [:account_id, :id], unique: true, name: 'rel_document_tenant_ref'
    create_table :jrc_relationship_document_versions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: { to_table: :jrc_relationship_customer_documents }
      t.references :uploaded_by, null: false, foreign_key: { to_table: :users }
      t.integer :number, null: false
      t.date :valid_until
      t.string :change_reason, null: false
      t.timestamps
    end
    add_index :jrc_relationship_document_versions, [:document_id, :number], unique: true, name: 'rel_document_version_number'
    add_foreign_key :jrc_relationship_customer_documents, :jrc_relationship_assignments,
                    column: [:account_id, :assignment_id], primary_key: [:account_id, :id], name: 'rel_document_assignment_tenant'
    add_foreign_key :jrc_relationship_document_versions, :jrc_relationship_customer_documents,
                    column: [:account_id, :document_id], primary_key: [:account_id, :id], name: 'rel_document_version_tenant'
  end
end
