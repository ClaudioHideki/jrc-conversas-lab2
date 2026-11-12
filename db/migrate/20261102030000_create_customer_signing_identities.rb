class CreateCustomerSigningIdentities < ActiveRecord::Migration[7.1]
  def change
    add_index :contacts, %i[account_id id], unique: true, name: 'jrc_contact_signing_tenant_ref'
    create_table :jrc_customer_signing_identities do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.text :personal_tax_identifier, null: false
      t.string :lookup_digest, null: false
      t.integer :revision, null: false, default: 1
      t.timestamps
    end
    add_index :jrc_customer_signing_identities, %i[account_id contact_id], unique: true, name: 'jrc_signing_contact_once'
    add_index :jrc_customer_signing_identities, %i[account_id lookup_digest], unique: true, name: 'jrc_signing_identifier_once'
    add_index :jrc_customer_signing_identities, %i[account_id id], unique: true, name: 'jrc_signing_identity_tenant_ref'
    add_foreign_key :jrc_customer_signing_identities, :contacts, column: %i[account_id contact_id], primary_key: %i[account_id id],
                                                                 name: 'jrc_signing_identity_contact_tenant'
    add_check_constraint :jrc_customer_signing_identities, 'revision > 0', name: 'jrc_signing_identity_revision'
  end
end
