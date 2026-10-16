class CreateJrcFlowNativeRegistrations < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_flow_native_configurations do |t|
      t.references :account, null: false, index: { unique: true }, foreign_key: { on_delete: :restrict }
      t.references :created_by, null: false, foreign_key: { to_table: :users, on_delete: :restrict }
      t.string :broker_origin, null: false
      t.string :host_origin, null: false
      t.uuid :organization_id, null: false
      t.uuid :credential_id, null: false
      t.integer :credential_revision, null: false
      t.integer :destination_revision, null: false
      t.integer :account_credential_version, null: false
      t.integer :revision, null: false
      t.text :encrypted_outbound_credential, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_check_constraint :jrc_flow_native_configurations,
                         'revision>0 AND credential_revision>0 AND destination_revision>0 AND account_credential_version>0',
                         name: 'jrc_flow_configuration_revisions_positive'
    create_table :jrc_flow_native_registrations do |t|
      t.references :account, null: false, foreign_key: { on_delete: :restrict }
      t.references :created_by, null: false, foreign_key: { to_table: :users, on_delete: :restrict }
      t.references :account_user, foreign_key: { on_delete: :nullify }
      t.string :broker_origin, null: false
      t.string :host_origin, null: false
      t.uuid :organization_id, null: false
      t.uuid :challenge_id, null: false
      t.uuid :broker_registration_id
      t.uuid :credential_id, null: false
      t.integer :credential_revision, null: false
      t.integer :destination_revision, null: false
      t.integer :account_credential_version, null: false
      t.integer :revision, null: false, default: 1
      t.integer :broker_registration_revision
      t.string :state, null: false, default: 'PENDING'
      t.jsonb :tuple, null: false
      t.text :encrypted_outbound_credential
      t.text :encrypted_pending_callback
      t.string :callback_digest
      t.uuid :confirmation_nonce
      t.datetime :expires_at, null: false
      t.datetime :credential_expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :jrc_flow_native_registrations, [:account_id, :id], unique: true, name: 'jrc_flow_reg_account_id'
    add_index :jrc_flow_native_registrations, [:account_id, :broker_origin, :challenge_id], unique: true, name: 'jrc_flow_reg_challenge_unique'
    add_index :jrc_flow_native_registrations, :callback_digest, unique: true, where: 'callback_digest IS NOT NULL',
                                                                name: 'jrc_flow_callback_digest_unique'
    add_index :jrc_flow_native_registrations, :account_id, unique: true, where: "state='ACTIVE'", name: 'jrc_flow_active_account_unique'
    add_check_constraint :jrc_flow_native_registrations, "state IN ('PENDING','CHALLENGE_VERIFIED','ACTIVE','CANCELED','REVOKED')",
                         name: 'jrc_flow_state_valid'
    add_check_constraint :jrc_flow_native_registrations,
                         'revision>0 AND credential_revision>0 AND destination_revision>0 AND account_credential_version>0',
                         name: 'jrc_flow_revisions_positive'
    add_check_constraint :jrc_flow_native_registrations,
                         "state<>'ACTIVE' OR (broker_registration_id IS NOT NULL AND broker_registration_revision>0 " \
                         'AND callback_digest IS NOT NULL AND encrypted_outbound_credential IS NOT NULL ' \
                         'AND encrypted_pending_callback IS NULL)', name: 'jrc_flow_active_registration_complete'
    add_check_constraint :jrc_flow_native_registrations,
                         "state NOT IN ('CANCELED','REVOKED') OR (callback_digest IS NULL " \
                         'AND encrypted_outbound_credential IS NULL AND encrypted_pending_callback IS NULL ' \
                         'AND revoked_at IS NOT NULL)', name: 'jrc_flow_revoked_keys_removed'

    create_table :jrc_flow_native_bindings do |t|
      t.bigint :account_id, null: false
      t.bigint :registration_id, null: false
      t.bigint :inbox_id, null: false
      t.uuid :integration_id, null: false
      t.uuid :channel_id, null: false
      t.string :transport, null: false
      t.string :provider
      t.integer :registration_revision, null: false
      t.timestamps
    end
    add_foreign_key :jrc_flow_native_bindings, :jrc_flow_native_registrations, column: [:account_id, :registration_id],
                                                                               primary_key: [:account_id, :id], on_delete: :restrict
    add_foreign_key :jrc_flow_native_bindings, :inboxes, column: [:account_id, :inbox_id], primary_key: [:account_id, :id], on_delete: :restrict
    add_index :jrc_flow_native_bindings, [:registration_id, :inbox_id], unique: true, name: 'jrc_flow_binding_inbox_unique'
    add_index :jrc_flow_native_bindings, [:registration_id, :integration_id], unique: true, name: 'jrc_flow_binding_integration_unique'
    add_check_constraint :jrc_flow_native_bindings, "transport IN ('BROKER_TRANSPORT','CENTRAL_TRANSPORT') AND registration_revision>0",
                         name: 'jrc_flow_binding_transport_revision'

    create_table :jrc_flow_native_session_handles do |t|
      t.bigint :account_id, null: false
      t.bigint :registration_id, null: false
      t.references :user, null: false, foreign_key: { on_delete: :restrict }
      t.uuid :broker_session_id, null: false
      t.uuid :nonce, null: false
      t.uuid :public_id, null: false
      t.text :encrypted_session_bearer
      t.boolean :remote_close_pending, null: false, default: true
      t.integer :credential_revision, null: false
      t.datetime :expires_at, null: false
      t.datetime :closed_at
      t.timestamps
    end
    add_foreign_key :jrc_flow_native_session_handles, :jrc_flow_native_registrations, column: [:account_id, :registration_id],
                                                                                      primary_key: [:account_id, :id], on_delete: :restrict
    add_index :jrc_flow_native_session_handles, :nonce, unique: true
    add_index :jrc_flow_native_session_handles, :public_id, unique: true
    add_index :jrc_flow_native_session_handles, :broker_session_id, unique: true
    # No cascade removes challenge/session tombstones or uncertain effect evidence.
    # AccountUser nullification permits membership loss; every use rechecks current membership.
  end
end
