class AddCustomerEconomicGroups < ActiveRecord::Migration[7.1]
  def up
    create_table :jrc_customer_economic_groups do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.text :name, null: false
      t.text :description
      t.bigint :principal_company_id
      t.timestamps
    end
    # Legacy names are text, including values larger than a btree key. Keep them
    # byte-for-byte instead of truncating, folding case or merging old groups.
    add_index :jrc_customer_economic_groups, 'account_id, md5(name)', unique: true, name: 'customer_economic_group_name'
    add_foreign_key :jrc_customer_economic_groups, :companies, column: %i[account_id principal_company_id],
                                                               primary_key: %i[account_id id], name: 'customer_economic_group_principal_account'
    execute <<~SQL.squish
      INSERT INTO jrc_customer_economic_groups (account_id, name, created_at, updated_at)
      SELECT account_id, economic_group, MIN(created_at), MAX(updated_at)
      FROM companies WHERE economic_group IS NOT NULL AND btrim(economic_group) <> ''
      GROUP BY account_id, economic_group
    SQL
  end

  def down
    used = select_value('SELECT id FROM jrc_customer_economic_groups LIMIT 1')
    raise ActiveRecord::IrreversibleMigration, 'Preserve economic groups before rollback' if used

    drop_table :jrc_customer_economic_groups
  end
end
