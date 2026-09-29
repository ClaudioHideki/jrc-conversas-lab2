class ExpandJrcCrmSalesGoals < ActiveRecord::Migration[7.1]
  def change
    change_table :jrc_crm_sales_goals, bulk: true do |t|
      t.string :name
      t.text :description
      t.string :status, null: false, default: 'draft'
      t.string :period_kind, null: false, default: 'monthly'
      t.string :calculation_method, null: false, default: 'approved_orders'
      t.string :currency, null: false, default: 'BRL'
      t.bigint :team_id
      t.jsonb :allocations, null: false, default: []
      t.jsonb :product_targets, null: false, default: []
      t.jsonb :indicators, null: false, default: []
      t.jsonb :settings, null: false, default: {}
      t.datetime :published_at
    end
    add_index :jrc_crm_sales_goals, :team_id
    add_index :jrc_crm_sales_goals, [:account_id, :status]
  end
end
