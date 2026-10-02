# Additive only: no historical row is rewritten by this migration.
class ExtendJrcCustomerMaster < ActiveRecord::Migration[7.1]
  def up
    execute "SET LOCAL lock_timeout = '5s'"
    add_column :companies, :person_kind, :string, default: 'organization', null: false
    add_column :companies, :relationship_type, :string, default: 'other', null: false
    %i[trade_name tax_id state_registration municipal_registration segment size website
       email phone_number source economic_group].each { |column| add_column :companies, column, :string }
    add_column :companies, :parent_company_id, :bigint
    add_column :companies, :owner_id, :integer
    add_column :companies, :active, :boolean, default: true, null: false
    add_column :jrc_crm_organizations, :company_id, :bigint
    add_column :jrc_crm_leads, :company_id, :bigint
    add_column :contacts, :job_title, :string
    add_column :contacts, :department, :string
    add_column :contacts, :registration_status, :string, default: 'provisional', null: false

    create_table :company_addresses do |t|
      t.bigint :account_id, null: false
      t.bigint :company_id, null: false
      t.string :address_type, null: false, default: 'business'
      %i[postal_code street number complement district city state].each { |column| t.string column }
      t.string :country, null: false, default: 'BR'
      t.timestamps
    end
    create_table :contact_points do |t|
      t.bigint :account_id, null: false
      t.bigint :contact_id, null: false
      t.string :kind, null: false
      t.string :value, null: false
      t.string :normalized_value, null: false
      t.string :label
      t.timestamps
    end
    add_check_constraint :companies, "person_kind IN ('organization','individual')", name: 'jrc_master_person_kind', validate: false
    add_check_constraint :companies,
                         "relationship_type IN ('prospect','lead','customer','former_customer','partner','supplier','internal','other')",
                         name: 'jrc_master_relationship_type', validate: false
    add_check_constraint :companies, 'parent_company_id IS NULL OR parent_company_id <> id', name: 'jrc_master_not_own_parent', validate: false
    add_check_constraint :contacts, "registration_status IN ('provisional','registered')", name: 'jrc_master_registration_status', validate: false
    add_check_constraint :company_addresses,
                         "address_type IN ('tax','billing','business','installation','branch','other')", name: 'jrc_master_address_type'
    add_check_constraint :contact_points,
                         "kind IN ('mobile','phone','whatsapp','whatsapp_business','extension','email','corporate_email','alternate_email')",
                         name: 'jrc_master_contact_point_kind'
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Disable jrc_customer_master to revert the interface; do not discard customer data.'
  end
end
