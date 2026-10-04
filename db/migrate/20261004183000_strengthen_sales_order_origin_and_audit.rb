class StrengthenSalesOrderOriginAndAudit < ActiveRecord::Migration[7.1]
  def up
    add_column :jrc_crm_sales_orders, :order_origin, :string unless column_exists?(:jrc_crm_sales_orders, :order_origin)
    add_column :jrc_crm_sales_orders, :proposal_version, :integer unless column_exists?(:jrc_crm_sales_orders, :proposal_version)
    add_column :jrc_crm_sales_orders, :created_by_id, :bigint unless column_exists?(:jrc_crm_sales_orders, :created_by_id)

    execute <<~SQL.squish
      UPDATE jrc_crm_sales_orders
      SET order_origin = CASE
        WHEN proposal_id IS NOT NULL THEN 'proposal_deal'
        WHEN deal_id IS NOT NULL THEN 'proposal_deal'
        ELSE 'direct_sale'
      END
      WHERE order_origin IS NULL OR order_origin = ''
    SQL

    change_column_default :jrc_crm_sales_orders, :order_origin, 'direct_sale'
    change_column_null :jrc_crm_sales_orders, :order_origin, false

    execute <<~SQL.squish
      UPDATE jrc_crm_sales_orders AS orders
      SET proposal_version = proposals.version_number
      FROM jrc_crm_proposals AS proposals
      WHERE orders.proposal_id = proposals.id
        AND orders.proposal_version IS NULL
    SQL

    add_index :jrc_crm_sales_orders, [:account_id, :order_origin], if_not_exists: true,
              name: 'idx_jrc_crm_orders_account_origin'
    add_index :jrc_crm_sales_orders, :created_by_id, if_not_exists: true
    add_foreign_key :jrc_crm_sales_orders, :users, column: :created_by_id, if_not_exists: true
  end

  def down
    remove_foreign_key :jrc_crm_sales_orders, column: :created_by_id if foreign_key_exists?(:jrc_crm_sales_orders, :users, column: :created_by_id)
    remove_index :jrc_crm_sales_orders, :created_by_id if index_exists?(:jrc_crm_sales_orders, :created_by_id)
    remove_index :jrc_crm_sales_orders, name: 'idx_jrc_crm_orders_account_origin' if index_exists?(:jrc_crm_sales_orders, [:account_id, :order_origin], name: 'idx_jrc_crm_orders_account_origin')
    remove_column :jrc_crm_sales_orders, :created_by_id if column_exists?(:jrc_crm_sales_orders, :created_by_id)
    remove_column :jrc_crm_sales_orders, :proposal_version if column_exists?(:jrc_crm_sales_orders, :proposal_version)
    remove_column :jrc_crm_sales_orders, :order_origin if column_exists?(:jrc_crm_sales_orders, :order_origin)
  end
end
