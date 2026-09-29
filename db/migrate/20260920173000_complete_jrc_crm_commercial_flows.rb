class CompleteJrcCrmCommercialFlows < ActiveRecord::Migration[7.1]
  def change
    change_table :jrc_crm_contracts, bulk: true do |t|
      t.string :signature_status, null: false, default: 'not_started'
      t.string :signature_mode
      t.string :signature_provider
      t.string :signature_external_id
      t.string :signed_by_name
      t.datetime :signed_at
      t.jsonb :lifecycle_metadata, null: false, default: {}
      t.text :content_override
    end

    add_reference :jrc_crm_contracts, :source_contract, foreign_key: { to_table: :jrc_crm_contracts }, index: true

    change_table :jrc_crm_sales_commissions, bulk: true do |t|
      t.jsonb :calculation, null: false, default: {}
      t.decimal :goal_attainment_percent, precision: 8, scale: 3
      t.decimal :share_percent, precision: 8, scale: 3, null: false, default: 100
      t.string :event_key
      t.datetime :accrued_at
    end

    add_index :jrc_crm_sales_commissions, :event_key
  end
end
