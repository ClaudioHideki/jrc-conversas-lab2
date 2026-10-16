class PreparePabxApiAndCallRecords < ActiveRecord::Migration[7.1]
  def change
    add_column :telephony_integrations, :pabx_settings, :jsonb, default: {}, null: false
    add_column :telephony_integrations, :pabx_sync_state, :jsonb, default: {}, null: false
    add_column :telephony_integrations, :pabx_username, :text
    add_column :telephony_integrations, :pabx_password, :text

    create_table :telephony_call_records do |t|
      t.references :account, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :external_tenant, null: false
      t.string :external_unique_id, null: false
      t.string :extension, null: false
      t.string :caller
      t.string :callee
      t.string :direction
      t.string :status
      t.datetime :started_at
      t.integer :duration_seconds
      t.integer :answered_seconds
      t.boolean :has_recording, default: false, null: false
      t.string :recording_reference
      t.datetime :synced_at, null: false
      t.timestamps
    end
    add_index :telephony_call_records, [:account_id, :provider, :external_tenant, :external_unique_id],
              unique: true, name: 'idx_telephony_cdr_external_identity'
    add_index :telephony_call_records, [:account_id, :provider, :external_tenant, :extension, :started_at],
              name: 'idx_telephony_cdr_extension_history'
  end
end
