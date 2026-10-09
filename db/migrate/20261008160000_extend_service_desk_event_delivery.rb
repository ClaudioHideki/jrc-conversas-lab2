class ExtendServiceDeskEventDelivery < ActiveRecord::Migration[7.1]
  TABLE = :jrc_service_desk_notification_deliveries

  def up
    add_source_columns
    add_source_constraints
    add_attempt_keys
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Preserve delivery origins, attempts and reconciliation; use reviewed forward recovery'
  end

  private

  def add_source_columns
    change_column_null TABLE, :ticket_note_id, true
    add_column TABLE, :ticket_event_id, :bigint
    add_column TABLE, :source_snapshot, :jsonb, null: false, default: {}
    add_column TABLE, :source_digest, :string
    add_column TABLE, :attempt_number, :integer, null: false, default: 1
    add_column TABLE, :original_delivery_id, :bigint
    add_column TABLE, :request_key, :string
    add_column TABLE, :request_fingerprint, :string
    add_column TABLE, :read_at, :datetime
    add_column TABLE, :reconciled_at, :datetime
    add_index :jrc_service_desk_ticket_events, %i[account_id unit_id ticket_id id], unique: true, name: 'jrc_sd_r2_event_scope_ref'
    add_index TABLE, %i[account_id unit_id ticket_id id], unique: true, name: 'jrc_sd_r2_delivery_scope_ref'
  end

  def add_source_constraints
    add_check_constraint TABLE, '(ticket_note_id IS NULL) <> (ticket_event_id IS NULL)', name: 'jrc_sd_delivery_one_origin'
    add_check_constraint TABLE, 'attempt_number > 0', name: 'jrc_sd_delivery_attempt_positive'
    add_check_constraint TABLE, 'original_delivery_id IS NULL OR original_delivery_id <> id', name: 'jrc_sd_delivery_original_distinct'
    add_foreign_key TABLE, :jrc_service_desk_ticket_events,
                    column: %i[account_id unit_id ticket_id ticket_event_id], primary_key: %i[account_id unit_id ticket_id id],
                    name: 'jrc_sd_delivery_event_scope_fk'
    add_foreign_key TABLE, TABLE, column: %i[account_id unit_id ticket_id original_delivery_id],
                                  primary_key: %i[account_id unit_id ticket_id id], name: 'jrc_sd_delivery_original_scope_fk'
  end

  def add_attempt_keys
    remove_index TABLE, name: 'jrc_sd_note_channel_unique'
    add_index TABLE, %i[ticket_note_id channel attempt_number], unique: true, where: 'ticket_note_id IS NOT NULL',
                                                                name: 'jrc_sd_note_channel_attempt_unique'
    execute <<~SQL.squish
      CREATE UNIQUE INDEX jrc_sd_event_recipient_attempt_unique
      ON jrc_service_desk_notification_deliveries
      (ticket_event_id, channel, COALESCE(recipient, ''), attempt_number)
      WHERE ticket_event_id IS NOT NULL
    SQL
    add_index TABLE, %i[account_id unit_id execution_membership_id request_key], unique: true,
                                                                                 where: 'request_key IS NOT NULL',
                                                                                 name: 'jrc_sd_delivery_manual_request_unique'
  end
end
