# frozen_string_literal: true

class CreateServiceDeskReportExports < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_service_desk_report_exports do |t|
      t.references :account, null: false, foreign_key: true
      t.references :unit, null: false, foreign_key: { to_table: :jrc_service_desk_units }
      t.references :account_user, null: false, foreign_key: true
      t.string :format, null: false
      t.string :state, null: false, default: 'queued'
      t.jsonb :filters, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.integer :record_count
      t.integer :expected_count, null: false
      t.string :authorization_signature
      t.string :error_code
      t.datetime :observed_at
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :jrc_service_desk_report_exports, %i[account_id account_user_id created_at], name: 'jrc_sd_report_exports_owner'
  end
end
