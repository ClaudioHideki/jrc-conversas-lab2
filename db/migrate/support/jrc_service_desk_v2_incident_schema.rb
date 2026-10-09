# frozen_string_literal: true

module JrcServiceDeskV2IncidentSchema
  private

  def create_incidents
    create_table :jrc_service_desk_incidents do |table|
      incidents_columns(table)
      table.timestamps
    end
    add_index :jrc_service_desk_incidents, %i[account_id unit_id id], unique: true, name: 'jrc_sd_incident_scope_ref'
    add_foreign_key :jrc_service_desk_incidents, :jrc_service_desk_units,
                    column: %i[account_id unit_id], primary_key: %i[account_id id], name: 'jrc_sd_incident_unit_fk'
    add_foreign_key :jrc_service_desk_incidents, :jrc_service_desk_tickets,
                    column: %i[account_id unit_id primary_ticket_id], primary_key: %i[account_id unit_id id], name: 'jrc_sd_incident_primary_fk'
    membership_fk(:jrc_service_desk_incidents, :created_by_membership_id)
    add_index :jrc_service_desk_incidents, %i[account_id unit_id created_by_membership_id idempotency_key], unique: true,
                                                                                                            name: 'jrc_sd_incident_request_unique'
    add_column :jrc_service_desk_tickets, :incident_id, :bigint
    add_foreign_key :jrc_service_desk_tickets, :jrc_service_desk_incidents,
                    column: %i[account_id unit_id incident_id], primary_key: %i[account_id unit_id id], name: 'jrc_sd_ticket_incident_fk'
  end

  def incident_history_columns(table)
    table.string :idempotency_key, null: false, limit: 120
    table.string :request_fingerprint, null: false, limit: 64
    table.integer :lock_version, null: false, default: 0
  end

  def incidents_columns(table)
    table.bigint :account_id, null: false
    table.bigint :unit_id, null: false
    table.bigint :created_by_membership_id, null: false
    table.bigint :primary_ticket_id
    table.string :title, null: false, limit: 255
    table.text :description
    table.string :severity, null: false
    table.string :status, null: false, default: 'open'
    table.text :impact
    table.text :cause
    table.text :workaround
    table.text :resolution
    table.datetime :started_at, null: false
    table.datetime :resolved_at
    incident_history_columns(table)
  end
end
