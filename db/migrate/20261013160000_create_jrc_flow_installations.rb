class CreateJrcFlowInstallations < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_flow_native_installations do |t|
      t.references :account, null: false, foreign_key: { on_delete: :restrict }
      t.references :created_by, null: false, foreign_key: { to_table: :users, on_delete: :restrict }
      t.references :registration, null: false, foreign_key: { to_table: :jrc_flow_native_registrations, on_delete: :restrict }
      t.uuid :grant_id, null: false
      t.integer :generation, null: false, default: 1
      t.string :state, null: false, default: 'PENDING'
      t.jsonb :tuple, null: false
      t.string :tuple_digest, null: false
      t.uuid :operation_nonce, null: false
      t.uuid :proof_nonce
      t.string :callback_digest, null: false
      t.text :encrypted_callback, null: false
      t.text :encrypted_grant
      t.text :encrypted_transfer_nonce
      t.text :encrypted_renew_callback
      t.text :encrypted_revoke_bearer
      t.datetime :lease_until
      t.datetime :operation_expires_at
      t.datetime :expires_at
      t.datetime :revoked_at
      t.boolean :remote_revoke_pending, null: false, default: false
      t.timestamps
    end
    add_index :jrc_flow_native_installations, [:account_id, :grant_id], unique: true, name: 'jrc_flow_installation_account_grant'
    add_index :jrc_flow_native_installations, :callback_digest, unique: true
    add_index :jrc_flow_native_installations, :operation_nonce, unique: true
    add_check_constraint :jrc_flow_native_installations,
                         "generation>0 AND state IN ('PENDING','ACTIVE','RENEWING','UNKNOWN','REVOKED') " \
                         "AND tuple_digest~'^[a-f0-9]{64}$' AND callback_digest~'^[a-f0-9]{64}$'", name: 'jrc_flow_installation_valid'
    add_check_constraint :jrc_flow_native_installations,
                         "state NOT IN ('ACTIVE','RENEWING') OR (encrypted_grant IS NOT NULL AND expires_at IS NOT NULL)",
                         name: 'jrc_flow_installation_active_complete'
    add_check_constraint :jrc_flow_native_installations,
                         "state<>'REVOKED' OR (encrypted_grant IS NULL AND encrypted_callback='' " \
                         'AND encrypted_renew_callback IS NULL AND revoked_at IS NOT NULL)', name: 'jrc_flow_installation_revoked_cipher'
  end
end
