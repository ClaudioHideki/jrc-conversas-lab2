class CreateJrcCrmBackofficeRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_crm_backoffice_requests do |t|
      t.references :account, null: false, foreign_key: true
      t.references :business_unit, foreign_key: { to_table: :jrc_crm_business_units }
      t.references :sales_order, null: false, foreign_key: { to_table: :jrc_crm_sales_orders }
      t.references :contract, foreign_key: { to_table: :jrc_crm_contracts }
      t.references :contact, foreign_key: true
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.string :request_number, null: false
      t.string :request_kind, null: false, default: 'fulfillment'
      t.string :stage, null: false, default: 'analysis'
      t.string :status, null: false, default: 'pending'
      t.string :priority, null: false, default: 'normal'
      t.string :title, null: false
      t.text :description
      t.datetime :due_at
      t.datetime :completed_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :jrc_crm_backoffice_requests, %i[account_id request_number], unique: true,
                                                                      name: 'idx_jrc_crm_backoffice_number'
    add_index :jrc_crm_backoffice_requests, %i[account_id sales_order_id request_kind], unique: true,
                                                                                where: "request_kind = 'fulfillment'",
                                                                                name: 'idx_jrc_crm_backoffice_order_kind'
    add_index :jrc_crm_backoffice_requests, %i[account_id status stage], name: 'idx_jrc_crm_backoffice_queue'
  end
end
