class ExpandJrcCrmCommercialCycle < ActiveRecord::Migration[7.1]
  def change
    change_table :jrc_crm_proposals, bulk: true do |t|
      t.bigint :shipping_cents, null: false, default: 0
      t.string :shipping_mode, null: false, default: 'not_applicable'
      t.string :payment_condition, null: false, default: 'cash'
      t.bigint :down_payment_cents, null: false, default: 0
      t.integer :installments_count, null: false, default: 1
      t.boolean :has_monthly_fee, null: false, default: true
    end

    create_table :jrc_crm_sales_orders do |t|
      t.references :account, null: false, foreign_key: true
      t.references :deal, null: false, foreign_key: { to_table: :jrc_crm_deals }
      t.references :proposal, foreign_key: { to_table: :jrc_crm_proposals }
      t.references :contact, foreign_key: true
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :order_number, null: false
      t.string :status, null: false, default: 'pending'
      t.bigint :products_cents, null: false, default: 0
      t.bigint :shipping_cents, null: false, default: 0
      t.bigint :discount_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.bigint :monthly_cents, null: false, default: 0
      t.string :payment_condition
      t.string :payment_method
      t.bigint :down_payment_cents, null: false, default: 0
      t.integer :installments_count, null: false, default: 1
      t.datetime :sold_at
      t.datetime :closed_at
      t.text :notes
      t.jsonb :snapshot, null: false, default: {}
      t.timestamps
    end
    add_index :jrc_crm_sales_orders, [:account_id, :order_number], unique: true, name: 'idx_jrc_crm_orders_account_number'

    create_table :jrc_crm_contracts do |t|
      t.references :account, null: false, foreign_key: true
      t.references :sales_order, null: false, foreign_key: { to_table: :jrc_crm_sales_orders }
      t.references :deal, null: false, foreign_key: { to_table: :jrc_crm_deals }
      t.references :contact, foreign_key: true
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :contract_number, null: false
      t.string :status, null: false, default: 'draft'
      t.date :starts_on
      t.date :ends_on
      t.integer :term_months
      t.string :renewal_type, default: 'automatic'
      t.string :adjustment_index, default: 'IPCA'
      t.bigint :monthly_cents, null: false, default: 0
      t.bigint :one_time_cents, null: false, default: 0
      t.date :next_adjustment_on
      t.text :notes
      t.timestamps
    end
    add_index :jrc_crm_contracts, [:account_id, :contract_number], unique: true, name: 'idx_jrc_crm_contracts_account_number'

    create_table :jrc_crm_sales_commissions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :sales_order, null: false, foreign_key: { to_table: :jrc_crm_sales_orders }
      t.references :user, null: false, foreign_key: true
      t.bigint :base_cents, null: false, default: 0
      t.decimal :rate_percent, precision: 7, scale: 3, null: false, default: 0
      t.bigint :commission_cents, null: false, default: 0
      t.string :status, null: false, default: 'forecast'
      t.datetime :released_at
      t.datetime :paid_at
      t.text :notes
      t.timestamps
    end
    add_index :jrc_crm_sales_commissions, [:account_id, :sales_order_id, :user_id], unique: true, name: 'idx_jrc_crm_commission_unique'

    create_table :jrc_crm_sales_goals do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.bigint :target_cents, null: false, default: 0
      t.timestamps
    end
    add_index :jrc_crm_sales_goals, [:account_id, :user_id, :period_start, :period_end], unique: true, name: 'idx_jrc_crm_goals_period'
  end
end
