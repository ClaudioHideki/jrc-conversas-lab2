class AddRelationshipDocumentResponsibility < ActiveRecord::Migration[7.1]
  def change
    add_reference :jrc_relationship_customer_documents, :responsible, foreign_key: { to_table: :users }, null: true
    add_column :jrc_relationship_customer_documents, :lock_version, :integer, null: false, default: 0
  end
end
