# No backfill is executed here. The reviewed task fills only unambiguous links.
class LinkJrcCustomerMasterOperations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    invalid = connection.select_values(<<~SQL)
      SELECT indexrelid::regclass::text FROM pg_index
      WHERE NOT indisvalid AND indexrelid::regclass::text LIKE '%jrc_master_%'
    SQL
    raise "Invalid master indexes require DBA review before retry: #{invalid.join(', ')}" if invalid.any?

    %i[jrc_service_desk_tickets jrc_projects_projects].each do |table|
      add_column table, :company_id, :bigint unless column_exists?(table, :company_id)
      add_index table, [:account_id, :company_id], algorithm: :concurrently, if_not_exists: true,
                name: "jrc_master_#{table}_company_idx"
      add_foreign_key table, :companies, column: [:account_id, :company_id], primary_key: [:account_id, :id],
                      validate: false, if_not_exists: true, name: "jrc_master_#{table}_company_fk"
    end
    # Reference IDs already exist; validate old rows separately, never repair them silently.
    %i[jrc_projects_projects jrc_crm_sales_orders jrc_crm_contracts jrc_crm_invoices jrc_crm_backoffice_requests].each do |table|
      add_foreign_key table, :contacts, column: [:account_id, :contact_id], primary_key: [:account_id, :id],
                      validate: false, if_not_exists: true, name: "jrc_master_#{table}_contact_fk"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Disable the feature; keep historical customer links.'
  end
end
