# frozen_string_literal: true

class ConfigureServiceDeskPortalCreation < ActiveRecord::Migration[7.1]
  def up
    configure_portal_authority
    create_portal_requests
    constrain_portal_provenance
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Preserve verified customer provenance and configured authority; use reviewed forward recovery'
  end

  private

  def configure_portal_authority
    add_column :jrc_service_desk_services, :portal_enabled, :boolean, null: false, default: false
    add_column :jrc_service_desk_services, :portal_inbox_id, :bigint
    add_column :jrc_service_desk_services, :portal_execution_membership_id, :bigint
    add_foreign_key :jrc_service_desk_services, :inboxes, column: %i[account_id portal_inbox_id],
                                                          primary_key: %i[account_id id], name: 'jrc_sd_service_portal_inbox_fk'
    add_foreign_key :jrc_service_desk_services, :jrc_service_desk_unit_memberships,
                    column: %i[account_id unit_id portal_execution_membership_id], primary_key: %i[account_id unit_id id],
                    name: 'jrc_sd_service_portal_executor_fk'
    add_check_constraint :jrc_service_desk_services,
                         'NOT portal_enabled OR (portal_inbox_id IS NOT NULL AND ' \
                         'portal_execution_membership_id IS NOT NULL AND default_priority_id IS NOT NULL)',
                         name: 'jrc_sd_service_portal_config_check'
    add_index :contacts, %i[account_id id], unique: true unless index_exists?(:contacts, %i[account_id id], unique: true)
    add_index :contact_inboxes, %i[contact_id inbox_id id], unique: true, name: 'jrc_sd_portal_identity_ref'
  end

  def create_portal_requests
    create_table :jrc_service_desk_portal_requests do |t|
      %i[account_id unit_id service_id ticket_id contact_id contact_inbox_id inbox_id execution_membership_id conversation_id
         message_id].each do |field|
        t.bigint field, null: false
      end
      t.string :request_key, null: false, limit: 120
      t.string :fingerprint, null: false, limit: 64
      t.string :service_revision, null: false, limit: 64
      t.jsonb :service_snapshot, null: false
      t.datetime :created_at, null: false
    end
    add_index :jrc_service_desk_portal_requests, %i[account_id contact_id request_key], unique: true, name: 'jrc_sd_portal_request_unique'
  end

  def constrain_portal_provenance
    targets = { service: :jrc_service_desk_services, ticket: :jrc_service_desk_tickets, execution_membership: :jrc_service_desk_unit_memberships }
    targets.each do |name, target|
      add_foreign_key :jrc_service_desk_portal_requests, target, column: [:account_id, :unit_id, "#{name}_id"],
                                                                 primary_key: %i[account_id unit_id id], name: "jrc_sd_portal_#{name}_fk"
    end
    %i[contact inbox].each do |name|
      add_foreign_key :jrc_service_desk_portal_requests, name.to_s.pluralize.to_sym, column: [:account_id, "#{name}_id"],
                                                                                     primary_key: %i[account_id id], name: "jrc_sd_portal_#{name}_fk"
    end
    add_foreign_key :jrc_service_desk_portal_requests, :contact_inboxes,
                    column: %i[contact_id inbox_id contact_inbox_id], primary_key: %i[contact_id inbox_id id], name: 'jrc_sd_portal_identity_fk'
    add_foreign_key :jrc_service_desk_portal_requests, :messages,
                    column: %i[account_id conversation_id message_id], primary_key: %i[account_id conversation_id id],
                    name: 'jrc_sd_portal_message_fk'
  end
end
