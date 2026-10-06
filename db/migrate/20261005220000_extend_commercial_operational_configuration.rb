class ExtendCommercialOperationalConfiguration < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_crm_products, :document_rules, :jsonb, null: false, default: []
    add_column :jrc_crm_contract_templates, :selection_rules, :jsonb, null: false, default: {}
    add_index :jrc_crm_backoffice_requests, [:account_id, :sales_order_id], unique: true,
      where: "request_kind = 'approval' AND metadata ->> 'source' = 'order_approval'",
      name: 'idx_jrc_crm_order_approval_source'
  end
end
