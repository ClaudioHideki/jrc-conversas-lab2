class CreateJrcBrokerHistoryReceipts < ActiveRecord::Migration[7.1]
  def up
    create_table :jrc_broker_history_receipts do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :message, foreign_key: { on_delete: :cascade }
      t.uuid :receipt_id, null: false
      t.uuid :organization_id, null: false
      t.uuid :integration_id, null: false
      t.uuid :history_account_identity, null: false
      t.uuid :source_id, null: false
      t.uuid :broker_conversation_id, null: false
      t.string :record_kind, null: false
      t.string :request_hash, null: false, limit: 64
      t.jsonb :recipient, null: false, default: {}
      t.datetime :created_at, null: false
    end
    create_indexes
    create_constraints
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Pause V2 without removing its durable receipts or historical messages'
  end

  private

  def create_indexes
    add_index :jrc_broker_history_receipts, :receipt_id, unique: true
    add_index :jrc_broker_history_receipts, [:account_id, :inbox_id, :integration_id, :history_account_identity, :record_kind, :source_id],
              unique: true, name: 'jrc_broker_history_fact_identity'
    add_index :jrc_broker_history_receipts, [:account_id, :message_id], unique: true, where: 'message_id IS NOT NULL',
                                                                        name: 'jrc_broker_history_message_identity'
  end

  def create_constraints
    add_check_constraint :jrc_broker_history_receipts, "request_hash ~ '^[a-f0-9]{64}$'", name: 'jrc_broker_history_hash'
    add_check_constraint :jrc_broker_history_receipts,
                         "(record_kind='CHAT' AND message_id IS NULL) OR (record_kind='MESSAGE' AND message_id IS NOT NULL)",
                         name: 'jrc_broker_history_receipt_kind'
  end
end
