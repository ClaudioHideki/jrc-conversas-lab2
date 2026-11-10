class AddRelationshipDocumentConfidentiality < ActiveRecord::Migration[7.1]
  def change
    # No automatic reclassification of pre-existing customer documents.
    add_column :jrc_relationship_customer_documents, :confidentiality, :string
    add_check_constraint :jrc_relationship_customer_documents,
      "confidentiality IS NULL OR confidentiality IN ('operational', 'restricted')", name: 'rel_doc_confidentiality_known'
  end
end
