class CompleteRelationshipNativeLineage < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_relationship_risk_cases, :mrr_at_risk_cents, :bigint
    add_column :jrc_relationship_risk_cases, :financial_snapshot, :jsonb, null: false, default: {}
    add_column :jrc_relationship_risk_cases, :financial_captured_at, :datetime
    add_reference :jrc_relationship_qbrs, :contract, foreign_key: { to_table: :jrc_crm_contracts }
    add_reference :jrc_relationship_qbrs, :product, foreign_key: { to_table: :jrc_crm_products }
  end
end
