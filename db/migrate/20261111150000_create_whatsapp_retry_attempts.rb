class CreateWhatsappRetryAttempts < ActiveRecord::Migration[7.1]
  def change
    execute "SET LOCAL lock_timeout = '5s'"
    create_table :whatsapp_retry_attempts do |t|
      t.references :account, type: :integer, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, type: :integer, null: false, foreign_key: { on_delete: :cascade }
      t.references :original_message, type: :integer, null: false, index: { unique: true }, foreign_key: { to_table: :messages, on_delete: :cascade }
      t.references :message, type: :integer, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.references :actor, type: :integer, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :state, null: false, default: 'queued'
      t.datetime :next_attempt_at
      t.integer :validation_failures, null: false, default: 0
      t.string :prior_error_code, null: false
      t.string :policy_version, null: false
      t.string :payload_fingerprint, null: false
      t.timestamps
    end
    add_index :whatsapp_retry_attempts, [:state, :updated_at]
    add_index :whatsapp_retry_attempts, [:state, :next_attempt_at]
    add_check_constraint :whatsapp_retry_attempts,
                         "state IN ('queued','submitting','accepted','delivered','read','failed','unknown','cancelled')",
                         name: 'whatsapp_retry_state'

    create_table :whatsapp_retry_receipts do |t|
      t.references :inbox, type: :integer, null: false, foreign_key: { on_delete: :cascade }
      t.references :whatsapp_retry_attempt, foreign_key: { on_delete: :cascade }
      t.string :source_id, null: false
      t.string :status, null: false
      t.string :error_code
      t.timestamps
    end
    add_index :whatsapp_retry_receipts, [:inbox_id, :source_id, :status], unique: true, name: 'whatsapp_retry_receipt_identity'
  end
end
