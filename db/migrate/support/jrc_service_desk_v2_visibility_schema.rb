# frozen_string_literal: true

module JrcServiceDeskV2VisibilitySchema
  private

  def add_native_delivery_keys
    add_index :inboxes, %i[account_id id], unique: true, name: 'jrc_sd_v2_inbox_ref' unless index_exists?(:inboxes, %i[account_id id], unique: true)
    add_index :messages, %i[account_id conversation_id id], unique: true, name: 'jrc_sd_v2_message_ref'
  end

  def extend_interaction_fields
    change_column :jrc_service_desk_ticket_notes, :visibility, :string, limit: 40, null: false, default: 'internal'
    remove_check_constraint :jrc_service_desk_ticket_notes, name: 'jrc_sd_note_internal'
    add_check_constraint :jrc_service_desk_ticket_notes,
                         "visibility IN ('internal','technical_team','customer','public_without_notification') AND btrim(body) <> ''",
                         name: 'jrc_sd_note_visibility'
    add_column :jrc_service_desk_ticket_notes, :audience_team_id, :bigint
    add_column :jrc_service_desk_ticket_notes, :notification_channels, :jsonb, null: false, default: []
    add_column :jrc_service_desk_ticket_notes, :notification_state, :string, null: false, default: 'not_requested'
    add_column :jrc_service_desk_ticket_notes, :previous_note_id, :bigint
    add_column :jrc_service_desk_ticket_notes, :publication_reason, :text
    add_column :jrc_service_desk_ticket_notes, :notification_conversations, :jsonb, null: false, default: {}
    scoped_team_fk(:jrc_service_desk_ticket_notes)
    add_index :jrc_service_desk_ticket_notes, %i[account_id unit_id ticket_id id], unique: true, name: 'jrc_sd_note_scope_ref'
    add_foreign_key :jrc_service_desk_ticket_notes, :jrc_service_desk_ticket_notes,
                    column: %i[account_id unit_id ticket_id previous_note_id], primary_key: %i[account_id unit_id ticket_id id],
                    name: 'jrc_sd_note_previous_fk'
  end

  def constrain_interaction_publication
    add_check_constraint :jrc_service_desk_ticket_notes,
                         "(visibility = 'technical_team') = (audience_team_id IS NOT NULL)", name: 'jrc_sd_note_team_audience'
    add_check_constraint :jrc_service_desk_ticket_notes,
                         "visibility = 'customer' OR notification_channels = '[]'::jsonb", name: 'jrc_sd_note_notifications'
    add_check_constraint :jrc_service_desk_ticket_notes,
                         'previous_note_id IS NULL OR (publication_reason IS NOT NULL AND ' \
                         "btrim(publication_reason) <> '' AND previous_note_id <> id)",
                         name: 'jrc_sd_note_publication_reason'
  end

  def extend_event_visibility
    add_column :jrc_service_desk_ticket_events, :visibility, :string, null: false, default: 'internal', limit: 40
    add_column :jrc_service_desk_ticket_events, :audience_team_id, :bigint
    scoped_team_fk(:jrc_service_desk_ticket_events)
    add_index :jrc_service_desk_ticket_events,
              %i[account_id unit_id actor_membership_id correlation_id],
              unique: true,
              where: "event_type = 'ticket_claimed' AND correlation_id IS NOT NULL",
              name: 'jrc_sd_claim_request_unique'
  end

  def configure_distribution_columns
    add_column :jrc_service_desk_queues, :distribution_mode, :string, null: false, default: 'manual'
    add_column :jrc_service_desk_queues, :required_skills, :jsonb, null: false, default: []
    add_column :jrc_service_desk_queues, :ola_budget_seconds, :integer
    add_column :jrc_service_desk_queues, :ola_time_basis, :string
    add_column :jrc_service_desk_queues, :ola_pause_waiting, :boolean, null: false, default: false
    add_column :jrc_service_desk_unit_memberships, :availability, :string, null: false, default: 'unavailable'
    add_column :jrc_service_desk_unit_memberships, :capacity, :integer
    add_column :jrc_service_desk_unit_memberships, :skills, :jsonb, null: false, default: []
    add_check_constraint :jrc_service_desk_unit_memberships, 'capacity IS NULL OR capacity > 0', name: 'jrc_sd_capacity_positive'
  end
end
