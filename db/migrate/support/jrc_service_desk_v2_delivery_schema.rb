# frozen_string_literal: true

module JrcServiceDeskV2DeliverySchema
  private

  def notification_policies_columns(table)
    table.bigint :account_id, null: false
    table.bigint :unit_id, null: false
    table.bigint :published_by_membership_id, null: false
    table.string :event_type, null: false
    table.string :channel, null: false
    table.integer :version, null: false
    table.boolean :enabled, null: false, default: false
    table.bigint :inbox_id
    table.text :template, null: false
    table.string :template_version, null: false
    table.string :digest, null: false
  end

  def create_notification_deliveries
    create_table :jrc_service_desk_notification_deliveries do |table|
      notification_deliveries_columns(table)
      table.timestamps
    end
    scoped_ticket_keys(:jrc_service_desk_notification_deliveries)
    membership_fk(:jrc_service_desk_notification_deliveries, :execution_membership_id)
    add_foreign_key :jrc_service_desk_notification_deliveries, :conversations,
                    column: %i[account_id conversation_id], primary_key: %i[account_id id], name: 'jrc_sd_notification_delivery_conversation_fk'
    add_foreign_key :jrc_service_desk_notification_deliveries, :messages,
                    column: %i[account_id conversation_id message_id], primary_key: %i[account_id conversation_id id],
                    name: 'jrc_sd_notification_delivery_message_fk'
    add_foreign_key :jrc_service_desk_notification_deliveries, :jrc_service_desk_ticket_notes,
                    column: %i[account_id unit_id ticket_id ticket_note_id], primary_key: %i[account_id unit_id ticket_id id],
                    name: 'jrc_sd_notification_delivery_note_fk'
    add_foreign_key :jrc_service_desk_notification_deliveries, :jrc_service_desk_notification_policy_versions,
                    column: %i[account_id unit_id notification_policy_version_id], primary_key: %i[account_id unit_id id],
                    name: 'jrc_sd_notification_delivery_policy_fk'
    add_index :jrc_service_desk_notification_deliveries, %i[ticket_note_id channel], unique: true, name: 'jrc_sd_note_channel_unique'
  end

  def notification_receipt_columns(table)
    table.datetime :dispatch_started_at
    table.datetime :sent_at
    table.datetime :delivered_at
    table.integer :lock_version, null: false, default: 0
  end

  def notification_deliveries_columns(table)
    ticket_columns(table)
    table.bigint :ticket_note_id, null: false
    table.bigint :notification_policy_version_id
    table.bigint :execution_membership_id, null: false
    table.bigint :conversation_id
    table.bigint :message_id
    table.string :channel, null: false
    table.string :recipient
    table.string :state, null: false, default: 'blocked'
    table.string :reason
    table.string :provider_id
    table.string :payload_digest
    notification_receipt_columns(table)
  end

  def ola_clocks_columns(table)
    ticket_columns(table)
    table.bigint :queue_id, null: false
    table.bigint :sla_snapshot_id
    table.integer :budget_seconds, null: false
    table.string :time_basis, null: false
  end

  def ola_policy_columns(table)
    table.string :policy_revision, null: false
    table.string :state, null: false, default: 'running'
    table.datetime :started_at, null: false
    table.datetime :anchor_at, null: false
    table.datetime :due_at, null: false
    table.datetime :ended_at
    table.float :elapsed_seconds, null: false, default: 0
    table.integer :lock_version, null: false, default: 0
  end
end
