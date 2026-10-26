# frozen_string_literal: true

# Additive. Existing incident identities and ticket incident_id links are retained.
class AddIncidentProblemWorkspaces < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_service_desk_incidents, :service_id, :bigint
    add_column :jrc_service_desk_incidents, :category_id, :bigint
    add_column :jrc_service_desk_incidents, :closed_at, :datetime
    add_column :jrc_service_desk_incidents, :details, :jsonb, null: false, default: {}
    add_check_constraint :jrc_service_desk_incidents, "jsonb_typeof(details) = 'object'", name: 'jrc_sd_case_details_object'
    add_index :jrc_service_desk_incidents, %i[account_id unit_id resource_kind status created_at], name: 'jrc_sd_case_board_idx'
    %i[service category].each do |name|
      add_foreign_key :jrc_service_desk_incidents, "jrc_service_desk_#{name.to_s.pluralize}",
                      column: [:account_id, :unit_id, "#{name}_id"], primary_key: %i[account_id unit_id id], name: "jrc_sd_case_#{name}_fk"
    end

    create_table :jrc_service_desk_incident_entries do |t|
      t.bigint :account_id, null: false
      t.bigint :unit_id, null: false
      t.bigint :incident_id, null: false
      t.bigint :actor_membership_id, null: false
      t.string :event_type, null: false, limit: 60
      t.text :body
      t.jsonb :data, null: false, default: {}
      t.string :idempotency_key, null: false, limit: 120
      t.string :request_fingerprint, null: false, limit: 64
      t.datetime :created_at, null: false
    end
    add_index :jrc_service_desk_incident_entries, %i[account_id unit_id incident_id actor_membership_id idempotency_key],
              unique: true, name: 'jrc_sd_case_entry_request_unique'
    add_index :jrc_service_desk_incident_entries, %i[incident_id created_at id], name: 'jrc_sd_case_timeline_idx'
    scope_fk(:jrc_service_desk_incident_entries, :incident_id, :jrc_service_desk_incidents, 'entry_incident')
    scope_fk(:jrc_service_desk_incident_entries, :actor_membership_id, :jrc_service_desk_unit_memberships, 'entry_actor')

    create_table :jrc_service_desk_case_links do |t|
      t.bigint :account_id, null: false
      t.bigint :unit_id, null: false
      t.bigint :incident_id, null: false
      t.bigint :ticket_id
      t.bigint :related_incident_id
      t.bigint :created_by_membership_id, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_check_constraint :jrc_service_desk_case_links, '(ticket_id IS NULL) <> (related_incident_id IS NULL)', name: 'jrc_sd_case_link_one_target'
    add_check_constraint :jrc_service_desk_case_links, 'related_incident_id IS NULL OR related_incident_id <> incident_id',
                         name: 'jrc_sd_case_no_self_link'
    add_index :jrc_service_desk_case_links, %i[incident_id ticket_id], unique: true, where: 'ticket_id IS NOT NULL', name: 'jrc_sd_case_ticket_unique'
    add_index :jrc_service_desk_case_links, %i[incident_id related_incident_id], unique: true, where: 'related_incident_id IS NOT NULL',
                                                                                 name: 'jrc_sd_case_incident_unique'
    add_index :jrc_service_desk_case_links, %i[ticket_id active], name: 'jrc_sd_case_ticket_reverse'
    add_index :jrc_service_desk_case_links, %i[related_incident_id active], name: 'jrc_sd_case_problem_reverse'
    scope_fk(:jrc_service_desk_case_links, :incident_id, :jrc_service_desk_incidents, 'link_source')
    scope_fk(:jrc_service_desk_case_links, :related_incident_id, :jrc_service_desk_incidents, 'link_target')
    scope_fk(:jrc_service_desk_case_links, :ticket_id, :jrc_service_desk_tickets, 'link_ticket')
    scope_fk(:jrc_service_desk_case_links, :created_by_membership_id, :jrc_service_desk_unit_memberships, 'link_actor')
  end

  private

  def scope_fk(table, field, target, name)
    add_foreign_key table, target, column: [:account_id, :unit_id, field], primary_key: %i[account_id unit_id id], name: "jrc_sd_case_#{name}_fk"
  end
end
