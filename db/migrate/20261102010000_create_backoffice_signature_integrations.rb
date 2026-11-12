class CreateBackofficeSignatureIntegrations < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_backoffice_signature_integrations do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true, name: 'bo_signature_account' }
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :public_id, null: false
      t.string :environment, null: false, default: 'demo'
      t.string :integration_key, null: false
      t.string :impersonated_user_id, null: false
      t.string :external_account_id, null: false
      t.text :encrypted_credentials, null: false
      t.integer :revision, null: false, default: 1
      t.boolean :enabled, null: false, default: false
      t.datetime :authorization_checked_at
      t.datetime :connect_checked_at
      t.timestamps
    end
    add_index :jrc_backoffice_signature_integrations, :public_id, unique: true, name: 'bo_signature_public_ref'
    add_index :jrc_backoffice_signature_integrations, %i[account_id id], unique: true, name: 'bo_signature_tenant_ref'
    add_check_constraint :jrc_backoffice_signature_integrations, "environment IN ('demo','production')", name: 'bo_signature_environment'
    add_check_constraint :jrc_backoffice_signature_integrations, 'revision > 0', name: 'bo_signature_revision'
  end
end
