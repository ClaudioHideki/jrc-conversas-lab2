class CompleteJrcCustomerMasterCompanyProfile < ActiveRecord::Migration[7.1]
  def up
    execute "SET LOCAL lock_timeout = '5s'"

    add_column :companies, :customer_code, :string
    add_column :companies, :relationship_tags, :jsonb, null: false, default: []
    add_column :companies, :tags, :jsonb, null: false, default: []
    add_column :companies, :created_by_id, :bigint
    add_column :companies, :updated_by_id, :bigint

    execute <<~SQL.squish
      UPDATE companies
      SET customer_code = 'EMP-' || LPAD(id::text, 6, '0')
      WHERE customer_code IS NULL
    SQL

    add_index :companies, %i[account_id customer_code], unique: true, name: 'idx_companies_account_customer_code'
    add_index :companies, :created_by_id
    add_index :companies, :updated_by_id
    add_foreign_key :companies, :users, column: :created_by_id, on_delete: :nullify
    add_foreign_key :companies, :users, column: :updated_by_id, on_delete: :nullify

    create_table :jrc_customer_taxonomies do |t|
      t.bigint :account_id, null: false
      t.string :kind, null: false
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    execute 'CREATE UNIQUE INDEX idx_jrc_customer_taxonomies_unique ON jrc_customer_taxonomies (account_id, kind, LOWER(name))'
    add_index :jrc_customer_taxonomies, %i[account_id kind active position], name: 'idx_jrc_customer_taxonomies_directory'
    add_foreign_key :jrc_customer_taxonomies, :accounts, on_delete: :cascade
    add_check_constraint :jrc_customer_taxonomies, "kind IN ('segment')", name: 'jrc_customer_taxonomy_kind'

    execute <<~SQL.squish
      INSERT INTO jrc_customer_taxonomies (account_id, kind, name, active, position, created_at, updated_at)
      SELECT account_id, 'segment', BTRIM(segment), TRUE, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM companies
      WHERE segment IS NOT NULL AND BTRIM(segment) <> ''
      GROUP BY account_id, BTRIM(segment)
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Customer master profile fields and taxonomy values can contain business data; revert through an explicit data migration.'
  end
end
