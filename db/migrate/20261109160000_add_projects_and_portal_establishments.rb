# frozen_string_literal: true

class AddProjectsAndPortalEstablishments < ActiveRecord::Migration[7.1]
  def change
    add_column :account_users, :jrc_projects_permissions, :jsonb, default: {}, null: false
    add_check_constraint :account_users, "jsonb_typeof(jrc_projects_permissions) = 'object'", name: 'jrc_project_permissions_object'
    add_column :jrc_service_desk_portal_grants, :establishment_ids, :jsonb, default: [], null: false
    add_check_constraint :jrc_service_desk_portal_grants,
                         "jsonb_typeof(establishment_ids) = 'array' AND jsonb_array_length(establishment_ids) <= 1000",
                         name: 'jrc_sd_grant_establishments'
    add_column :jrc_service_desk_tickets, :establishment_company_id, :bigint
    add_index :jrc_service_desk_tickets, %i[account_id establishment_company_id], name: 'jrc_sd_ticket_establishment'
    add_foreign_key :jrc_service_desk_tickets, :companies, column: %i[account_id establishment_company_id],
                    primary_key: %i[account_id id], name: 'jrc_sd_establishment_account_fk'
  end
end
