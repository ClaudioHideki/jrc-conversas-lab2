class AddCompanyContactContextToContacts < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :contacts, :company_role, :string, limit: 40
    add_column :contacts, :company_primary, :boolean, null: false, default: false
    add_column :contacts, :company_contact_status, :string, null: false, default: 'active', limit: 20
    add_check_constraint :contacts,
                         "NOT company_primary OR (company_id IS NOT NULL AND company_contact_status = 'active')",
                         name: 'contacts_company_primary_requires_active_link',
                         validate: false
    validate_check_constraint :contacts, name: 'contacts_company_primary_requires_active_link'
    add_index :contacts, %i[account_id company_id],
              unique: true,
              where: 'company_primary',
              name: 'contacts_one_primary_per_company',
              algorithm: :concurrently
  end

  def down
    used = select_value("SELECT id FROM contacts WHERE company_primary OR company_role IS NOT NULL OR company_contact_status <> 'active' LIMIT 1")
    raise ActiveRecord::IrreversibleMigration, 'Preserve the company contact context before rollback' if used

    remove_index :contacts, name: 'contacts_one_primary_per_company', algorithm: :concurrently
    remove_check_constraint :contacts, name: 'contacts_company_primary_requires_active_link'
    remove_column :contacts, :company_contact_status
    remove_column :contacts, :company_primary
    remove_column :contacts, :company_role
  end
end
