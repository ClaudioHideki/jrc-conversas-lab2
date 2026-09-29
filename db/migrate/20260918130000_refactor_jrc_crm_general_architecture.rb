class RefactorJrcCrmGeneralArchitecture < ActiveRecord::Migration[7.1]
  OPERATIONAL_TABLES = %i[
    jrc_crm_leads jrc_crm_deals jrc_crm_products jrc_crm_proposals
    jrc_crm_sales_orders jrc_crm_contracts jrc_crm_sales_goals
    jrc_crm_sales_commissions jrc_crm_activities
  ].freeze

  def change
    create_table :jrc_crm_business_units do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :code, null: false
      t.string :segment
      t.boolean :active, null: false, default: true
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_index :jrc_crm_business_units, %i[account_id code], unique: true, name: 'idx_jrc_crm_bu_account_code'

    create_table :jrc_crm_user_business_units do |t|
      t.references :account, null: false, foreign_key: true
      t.references :business_unit, null: false, foreign_key: { to_table: :jrc_crm_business_units }
      t.references :user, null: false, foreign_key: true
      t.string :scope, null: false, default: 'OWN'
      t.jsonb :permissions, null: false, default: {}
      t.timestamps
    end
    add_index :jrc_crm_user_business_units, %i[business_unit_id user_id], unique: true, name: 'idx_jrc_crm_user_bu_unique'

    OPERATIONAL_TABLES.each do |table|
      add_reference table, :business_unit, foreign_key: { to_table: :jrc_crm_business_units }, index: true
    end

    # Direct sales are valid when the business unit allows them.
    change_column_null :jrc_crm_sales_orders, :deal_id, true
    add_column :jrc_crm_sales_orders, :source_type, :string, null: false, default: 'proposal'

    create_table :jrc_crm_order_items do |t|
      t.references :sales_order, null: false, foreign_key: { to_table: :jrc_crm_sales_orders }
      t.references :product, foreign_key: { to_table: :jrc_crm_products }
      t.string :name, null: false
      t.decimal :quantity, precision: 14, scale: 3, null: false, default: 1
      t.bigint :unit_cents, null: false, default: 0
      t.bigint :discount_cents, null: false, default: 0
      t.bigint :one_time_cents, null: false, default: 0
      t.bigint :recurring_cents, null: false, default: 0
      t.jsonb :snapshot, null: false, default: {}
      t.timestamps
    end

    create_table :jrc_crm_contract_items do |t|
      t.references :contract, null: false, foreign_key: { to_table: :jrc_crm_contracts }
      t.references :product, foreign_key: { to_table: :jrc_crm_products }
      t.string :name, null: false
      t.decimal :quantity, precision: 14, scale: 3, null: false, default: 1
      t.bigint :one_time_cents, null: false, default: 0
      t.bigint :monthly_cents, null: false, default: 0
      t.date :starts_on
      t.string :status, null: false, default: 'pending'
      t.string :operational_identifier
      t.jsonb :snapshot, null: false, default: {}
      t.timestamps
    end

    change_table :jrc_crm_contracts, bulk: true do |t|
      t.string :contract_type
      t.string :payment_condition
      t.integer :due_day
      t.boolean :auto_renew, null: false, default: false
      t.integer :renewal_notice_days, null: false, default: 30
      t.integer :renewal_term_months
    end

    create_table :jrc_crm_invoices do |t|
      t.references :account, null: false, foreign_key: true
      t.references :business_unit, foreign_key: { to_table: :jrc_crm_business_units }
      t.references :contact, foreign_key: true
      t.references :sales_order, foreign_key: { to_table: :jrc_crm_sales_orders }
      t.references :contract, foreign_key: { to_table: :jrc_crm_contracts }
      t.string :invoice_number, null: false
      t.string :status, null: false, default: 'draft'
      t.date :competence_on
      t.date :issued_on
      t.date :due_on, null: false
      t.bigint :subtotal_cents, null: false, default: 0
      t.bigint :discount_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.bigint :balance_cents, null: false, default: 0
      t.string :payment_method
      t.jsonb :snapshot, null: false, default: {}
      t.timestamps
    end
    add_index :jrc_crm_invoices, %i[account_id invoice_number], unique: true, name: 'idx_jrc_crm_invoice_number'

    create_table :jrc_crm_payments do |t|
      t.references :account, null: false, foreign_key: true
      t.references :business_unit, foreign_key: { to_table: :jrc_crm_business_units }
      t.references :invoice, null: false, foreign_key: { to_table: :jrc_crm_invoices }
      t.bigint :amount_cents, null: false
      t.datetime :paid_at, null: false
      t.string :method
      t.string :external_id
      t.string :reconciliation_status, null: false, default: 'pending'
      t.bigint :interest_cents, null: false, default: 0
      t.bigint :penalty_cents, null: false, default: 0
      t.bigint :discount_cents, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :jrc_crm_payments, %i[account_id external_id], unique: true, where: 'external_id IS NOT NULL', name: 'idx_jrc_crm_payment_external'

    create_table :jrc_crm_commission_programs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :business_unit, foreign_key: { to_table: :jrc_crm_business_units }
      t.string :name, null: false
      t.string :release_condition, null: false, default: 'order_approved'
      t.date :starts_on
      t.date :ends_on
      t.boolean :active, null: false, default: true
      t.jsonb :rules, null: false, default: []
      t.timestamps
    end
    add_reference :jrc_crm_sales_commissions, :commission_program, foreign_key: { to_table: :jrc_crm_commission_programs }, index: true

    change_table :jrc_crm_sales_goals, bulk: true do |t|
      t.string :scope_kind, null: false, default: 'user'
      t.references :product, foreign_key: { to_table: :jrc_crm_products }
      t.string :metric, null: false, default: 'revenue'
      t.bigint :target_quantity
    end
  end
end
