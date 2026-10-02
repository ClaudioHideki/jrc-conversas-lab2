# Keep index builds out of a large DDL transaction. Legacy invalid links are
# reported by jrc:customer_master:backfill and must be reviewed before VALIDATE.
class GuardJrcCustomerMasterTenants < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    invalid = connection.select_values(<<~SQL)
      SELECT indexrelid::regclass::text FROM pg_index
      WHERE NOT indisvalid AND indexrelid::regclass::text LIKE '%jrc_master_%'
    SQL
    raise "Invalid master indexes require DBA review before retry: #{invalid.join(', ')}" if invalid.any?

    %i[companies contacts jrc_crm_organizations].each do |table|
      # Service Desk already supplies the contacts/account unique index in this base.
      next if index_exists?(table, [:account_id, :id], unique: true)

      add_index table, [:account_id, :id], unique: true, algorithm: :concurrently,
                if_not_exists: true, name: "jrc_master_#{table}_account_id"
    end
    add_index :companies, "account_id, (NULLIF(upper(regexp_replace(tax_id, '[^A-Za-z0-9]', '', 'g')), ''))",
              unique: true, algorithm: :concurrently, if_not_exists: true, name: 'jrc_master_company_tax_unique'
    add_index :companies, [:account_id, :relationship_type, :segment], algorithm: :concurrently,
              if_not_exists: true, name: 'jrc_master_company_filters'
    add_index :companies, [:account_id, :parent_company_id], algorithm: :concurrently,
              if_not_exists: true, name: 'jrc_master_company_parent'
    add_index :contacts, "account_id, (lower(trim(email)))", algorithm: :concurrently,
              if_not_exists: true, name: 'jrc_master_contact_normalized_email'
    add_index :contacts, "account_id, (regexp_replace(phone_number, '[^0-9]', '', 'g'))", algorithm: :concurrently,
              if_not_exists: true, name: 'jrc_master_contact_normalized_phone'
    add_index :company_addresses, [:account_id, :company_id], if_not_exists: true
    add_index :contact_points, [:account_id, :normalized_value], if_not_exists: true
    add_index :contact_points, [:contact_id, :kind, :normalized_value], unique: true,
              if_not_exists: true, name: 'jrc_master_contact_point_unique'
    add_index :jrc_crm_organizations, [:account_id, :company_id], algorithm: :concurrently, if_not_exists: true
    add_index :jrc_crm_leads, [:account_id, :company_id], algorithm: :concurrently, if_not_exists: true

    %i[contacts jrc_crm_organizations jrc_crm_leads jrc_crm_deals jrc_crm_activities company_addresses].each do |table|
      add_foreign_key table, :companies, column: [:account_id, :company_id], primary_key: [:account_id, :id],
                      validate: false, if_not_exists: true, name: "jrc_master_#{table}_company_fk"
    end
    add_foreign_key :companies, :companies, column: [:account_id, :parent_company_id], primary_key: [:account_id, :id],
                    validate: false, if_not_exists: true, name: 'jrc_master_company_parent_fk'
    add_foreign_key :contact_points, :contacts, column: [:account_id, :contact_id], primary_key: [:account_id, :id],
                    if_not_exists: true, name: 'jrc_master_contact_point_contact_fk'
    %i[jrc_crm_leads jrc_crm_deals jrc_crm_activities].each do |table|
      add_foreign_key table, :contacts, column: [:account_id, :contact_id], primary_key: [:account_id, :id],
                      validate: false, if_not_exists: true, name: "jrc_master_#{table}_contact_fk"
    end
    %i[jrc_crm_deals jrc_crm_activities].each do |table|
      add_foreign_key table, :jrc_crm_organizations, column: [:account_id, :organization_id], primary_key: [:account_id, :id],
                      validate: false, if_not_exists: true, name: "jrc_master_#{table}_organization_fk"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Review references and retained customer data before any manual schema reversal.'
  end
end
