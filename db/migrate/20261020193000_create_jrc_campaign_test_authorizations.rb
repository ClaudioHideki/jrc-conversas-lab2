class CreateJrcCampaignTestAuthorizations < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_campaign_test_authorizations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :recorded_by, null: false, foreign_key: { to_table: :users }
      t.references :test_delivery, foreign_key: { to_table: :jrc_campaign_test_deliveries }, index: { unique: true }
      t.string :phone_number, null: false
      t.text :evidence, null: false
      t.jsonb :connector_snapshot, null: false, default: {}
      t.datetime :granted_at, null: false
      t.datetime :consumed_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :jrc_campaign_test_authorizations, [:account_id, :inbox_id, :phone_number], unique: true,
              where: 'consumed_at IS NULL AND revoked_at IS NULL', name: 'idx_jrc_test_authorization_available'
  end
end
