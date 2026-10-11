# frozen_string_literal: true

# Preserve all existing grants and composite actor foreign keys. Audit actors are
# not operational grants, including after a native administrator is demoted.
class SeparateServiceDeskAdministrativeActors < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_service_desk_unit_memberships, :administrative_actor, :boolean, null: false, default: false
    remove_index :jrc_service_desk_unit_memberships, name: 'jrc_sd_membership_unique',
                 column: %i[account_id unit_id account_user_id], unique: true
    add_index :jrc_service_desk_unit_memberships, %i[account_id unit_id account_user_id administrative_actor],
              unique: true, name: 'jrc_sd_membership_unique'
    add_check_constraint :jrc_service_desk_unit_memberships,
                         "NOT administrative_actor OR (NOT active AND availability = 'unavailable' AND capacity IS NULL AND skills = '[]'::jsonb)",
                         name: 'jrc_sd_membership_audit_only'
  end
end
