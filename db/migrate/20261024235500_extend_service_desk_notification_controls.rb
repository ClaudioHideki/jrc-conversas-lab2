# frozen_string_literal: true

class ExtendServiceDeskNotificationControls < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_service_desk_notification_policy_versions, :settings, :jsonb, null: false, default: {}
    add_column :jrc_service_desk_notification_deliveries, :recipient_contact_id, :bigint
    add_column :jrc_service_desk_notification_deliveries, :not_before, :datetime
    add_foreign_key :jrc_service_desk_notification_deliveries, :contacts, column: [:account_id, :recipient_contact_id],
                                                                          primary_key: [:account_id, :id], name: 'jrc_sd_notification_contact_fk'
    remove_index :jrc_service_desk_notification_deliveries, [:ticket_note_id, :channel, :attempt_number], name: 'jrc_sd_note_channel_attempt_unique',
                                                                                                          unique: true, where: 'ticket_note_id IS NOT NULL'
    add_index :jrc_service_desk_notification_deliveries, 'ticket_note_id, channel, COALESCE(recipient_contact_id,0), attempt_number', unique: true,
                                                                                                                                      where: 'ticket_note_id IS NOT NULL', name: 'jrc_sd_note_recipient_attempt_unique'
  end
end
