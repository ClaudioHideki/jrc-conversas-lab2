class CreateJrcBrokerWebhookObligations < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_broker_webhook_obligations do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :message, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.bigint :inbox_id, null: false
      t.bigint :binding_id, null: false
      t.string :integration_id, null: false
      t.string :instance_id, null: false
      t.text :url, null: false
      t.jsonb :payload, null: false
      t.uuid :delivery_id, null: false, default: -> { 'gen_random_uuid()' }
      t.string :state, null: false, default: 'pending'
      t.integer :attempts, null: false, default: 0
      t.datetime :available_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.uuid :lease_token
      t.datetime :lease_until
      t.string :last_error_code
      t.timestamps
    end
    add_delivery_constraints
  end

  private

  def add_delivery_constraints
    add_index :jrc_broker_webhook_obligations, :delivery_id, unique: true
    add_index :jrc_broker_webhook_obligations, [:state, :available_at], name: 'idx_jrc_broker_obligations_due'
    add_check_constraint :jrc_broker_webhook_obligations,
                         "state IN ('pending','running','delivered','rejected','failed') AND attempts >= 0", name: 'jrc_broker_obligation_state'
  end
end
