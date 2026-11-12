class AddRelationshipDocumentRequirement < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_relationship_customer_documents, :requirement_key, :string, limit: 60
    add_index :jrc_relationship_customer_documents, [:account_id, :assignment_id, :requirement_key],
              unique: true, where: "status = 'active' AND requirement_key IS NOT NULL", name: 'rel_doc_active_requirement'
  end
end
