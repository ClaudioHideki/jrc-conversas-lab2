# frozen_string_literal: true

class AddServiceDeskRequesterPortalGrants < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_service_desk_portal_grants do |t|
      %i[account_id user_id company_id contact_id inbox_id contact_inbox_id granted_by_id].each { |field| t.bigint field, null: false }
      t.boolean :active, null: false, default: false
      t.string :role, null: false, default: 'requester'
      t.jsonb :visible_contact_ids, null: false, default: []
      t.boolean :expose_sla, null: false, default: false
      t.datetime :expires_at
      t.timestamps
    end
    add_index :jrc_service_desk_portal_grants, %i[user_id account_id company_id contact_inbox_id], unique: true, name: 'jrc_sd_pg_identity'
    add_index :jrc_service_desk_portal_grants, %i[user_id active], name: 'jrc_sd_pg_access'
    add_foreign_key :jrc_service_desk_portal_grants, :accounts
    add_foreign_key :jrc_service_desk_portal_grants, :users
    add_foreign_key :jrc_service_desk_portal_grants, :users, column: :granted_by_id
    { companies: :company_id, contacts: :contact_id, inboxes: :inbox_id }.each do |table, column|
      add_foreign_key :jrc_service_desk_portal_grants, table, column: [:account_id, column], primary_key: %i[account_id id],
                                                           name: "jrc_sd_pg_#{table}"
    end
    add_foreign_key :jrc_service_desk_portal_grants, :contact_inboxes, column: %i[contact_id inbox_id contact_inbox_id],
                                                                   primary_key: %i[contact_id inbox_id id], name: 'jrc_sd_pg_native_identity'
    add_check_constraint :jrc_service_desk_portal_grants, "role IN ('requester','manager','organization_admin')", name: 'jrc_sd_pg_role'
    add_check_constraint :jrc_service_desk_portal_grants,
                         "jsonb_typeof(visible_contact_ids) = 'array' AND jsonb_array_length(visible_contact_ids) <= 100",
                         name: 'jrc_sd_pg_visible_contacts'
  end
end
