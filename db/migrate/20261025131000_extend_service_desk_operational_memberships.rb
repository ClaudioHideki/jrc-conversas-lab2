# frozen_string_literal: true

# Additive configuration only. Existing assignments and audit actors are untouched.
class ExtendServiceDeskOperationalMemberships < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_service_desk_unit_memberships, :manual_assignment_enabled, :boolean, null: false, default: true
    add_column :jrc_service_desk_unit_memberships, :team_id, :bigint
    add_column :jrc_service_desk_unit_memberships, :queue_id, :bigint
    add_column :jrc_service_desk_unit_memberships, :restricted_supervision, :boolean, null: false, default: false
    add_column :jrc_service_desk_unit_memberships, :supervision_grants, :jsonb, null: false, default: []
    add_check_constraint :jrc_service_desk_unit_memberships, "jsonb_typeof(supervision_grants) = 'array'",
                         name: 'jrc_sd_membership_supervision_array'
    add_foreign_key :jrc_service_desk_unit_memberships, :teams, column: %i[account_id team_id], primary_key: %i[account_id id],
                    name: 'jrc_sd_membership_team_fk'
    add_foreign_key :jrc_service_desk_unit_memberships, :jrc_service_desk_queues,
                    column: %i[account_id unit_id queue_id], primary_key: %i[account_id unit_id id], name: 'jrc_sd_membership_queue_fk'
  end
end
