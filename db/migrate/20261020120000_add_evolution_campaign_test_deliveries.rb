class AddEvolutionCampaignTestDeliveries < ActiveRecord::Migration[7.1]
  def change
    # Historical evidence must not acquire an unverified purpose during migration.
    add_column :jrc_campaign_consents, :purpose, :string
    create_table :jrc_campaign_test_deliveries do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.string :idempotency_key, null: false
      t.string :payload_digest, null: false
      t.string :status, null: false, default: 'sending'
      t.string :phone_number, null: false
      t.string :external_id
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :jrc_campaign_test_deliveries, [:account_id, :idempotency_key], unique: true, name: 'idx_jrc_campaign_test_idempotency'
  end
end
