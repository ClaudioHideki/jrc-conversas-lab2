class AddMetaCampaignTracking < ActiveRecord::Migration[7.1]
  def change
    change_table :jrc_campaign_test_deliveries, bulk: true do |t|
      t.datetime :accepted_at
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :read_at
      t.datetime :failed_at
      t.string :error_code
    end
    add_index :jrc_campaign_test_deliveries, [:inbox_id, :external_id], name: 'idx_campaign_test_wamid'
    create_table :jrc_campaign_status_events do |t|
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.string :external_id, null: false
      t.string :status, null: false
      t.string :fingerprint, null: false
      t.jsonb :errors, null: false, default: []
      t.datetime :occurred_at, null: false
      t.datetime :matched_at
      t.timestamps
    end
    add_index :jrc_campaign_status_events, [:inbox_id, :fingerprint], unique: true, name: 'idx_campaign_status_idempotency'
    add_index :jrc_campaign_status_events, [:inbox_id, :external_id], name: 'idx_campaign_status_wamid'
  end
end
