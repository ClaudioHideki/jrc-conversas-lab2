# frozen_string_literal: true

class RecordServiceDeskClockAlertExecutions < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_service_desk_ticket_notes, :notification_context, :jsonb, default: {}, null: false
    create_table :jrc_service_desk_clock_alert_deliveries do |t|
      t.bigint :account_id, null: false
      t.bigint :unit_id, null: false
      t.bigint :ticket_id, null: false
      t.bigint :ticket_event_id, null: false
      t.bigint :recipient_account_user_id, null: false
      t.bigint :notification_id
      t.string :channel, null: false
      t.string :state, null: false, default: 'queued'
      t.string :reason
      t.integer :attempts, null: false, default: 0
      t.datetime :dispatch_started_at
      t.datetime :accepted_at
      t.timestamps
    end
    add_index :jrc_service_desk_clock_alert_deliveries, [:ticket_event_id, :recipient_account_user_id, :channel], unique: true,
                                                                                                                  name: 'jrc_sd_clock_alert_once'
    add_foreign_key :jrc_service_desk_clock_alert_deliveries, :jrc_service_desk_ticket_events,
                    column: [:account_id, :unit_id, :ticket_id, :ticket_event_id], primary_key: [:account_id, :unit_id, :ticket_id, :id], name: 'jrc_sd_clock_alert_origin'
    add_foreign_key :jrc_service_desk_clock_alert_deliveries, :jrc_service_desk_tickets, column: [:account_id, :unit_id, :ticket_id],
                                                                                         primary_key: [:account_id, :unit_id, :id], name: 'jrc_sd_clock_alert_ticket'
    add_foreign_key :jrc_service_desk_clock_alert_deliveries, :account_users, column: [:account_id, :recipient_account_user_id],
                                                                              primary_key: [:account_id, :id], name: 'jrc_sd_clock_alert_recipient'
    add_foreign_key :jrc_service_desk_clock_alert_deliveries, :notifications, column: :notification_id, on_delete: :nullify
  end
end
