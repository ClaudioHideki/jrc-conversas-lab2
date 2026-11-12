class CreateBackofficeSignatureNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_backoffice_signature_notifications do |t|
      t.references :account, null: false, foreign_key: true
      t.references :integration, null: false, foreign_key: { to_table: :jrc_backoffice_signature_integrations }
      t.integer :integration_revision, null: false
      t.string :body_sha256, null: false
      t.string :event_type, null: false
      t.string :envelope_id, null: false
      t.text :encrypted_payload, null: false
      t.string :state, null: false, default: 'received'
      t.datetime :provider_generated_at, null: false
      t.timestamps
    end
    add_index :jrc_backoffice_signature_notifications, %i[integration_id integration_revision body_sha256],
              unique: true, name: 'bo_signature_notification_dedup'
    add_index :jrc_backoffice_signature_notifications, %i[account_id envelope_id], name: 'bo_signature_notification_envelope'
    add_check_constraint :jrc_backoffice_signature_notifications, "state IN ('received','processed','ignored','failed')",
                         name: 'bo_signature_notification_state'
  end
end
