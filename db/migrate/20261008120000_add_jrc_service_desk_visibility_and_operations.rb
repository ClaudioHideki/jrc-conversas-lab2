# frozen_string_literal: true

require_relative 'support/jrc_service_desk_v2_visibility_schema'
require_relative 'support/jrc_service_desk_v2_work_schema'
require_relative 'support/jrc_service_desk_v2_incident_schema'
require_relative 'support/jrc_service_desk_v2_catalog_schema'
require_relative 'support/jrc_service_desk_v2_delivery_schema'

class AddJrcServiceDeskVisibilityAndOperations < ActiveRecord::Migration[7.1]
  include JrcServiceDeskV2VisibilitySchema
  include JrcServiceDeskV2WorkSchema
  include JrcServiceDeskV2IncidentSchema
  include JrcServiceDeskV2CatalogSchema
  include JrcServiceDeskV2DeliverySchema

  def up
    add_native_delivery_keys
    extend_interaction_fields
    constrain_interaction_publication
    extend_event_visibility
    configure_distribution_columns
    create_tasks
    create_approvals
    create_incidents
    extend_service_catalog
    create_notification_policies
    create_notification_deliveries
    create_ola_clocks
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Preserve interaction visibility, public history, tasks and approvals; use a reviewed forward recovery'
  end

  private

  def create_notification_policies
    create_table :jrc_service_desk_notification_policy_versions do |table|
      notification_policies_columns(table)
      table.datetime :created_at, null: false
    end
    add_index :jrc_service_desk_notification_policy_versions, %i[account_id unit_id event_type channel version],
              unique: true, name: 'jrc_sd_notification_policy_version_unique'
    add_index :jrc_service_desk_notification_policy_versions, %i[account_id unit_id id], unique: true,
                                                                                         name: 'jrc_sd_notification_policy_scope_ref'
    add_foreign_key :jrc_service_desk_notification_policy_versions, :jrc_service_desk_units,
                    column: %i[account_id unit_id], primary_key: %i[account_id id], name: 'jrc_sd_notification_policy_unit_fk'
    membership_fk(:jrc_service_desk_notification_policy_versions, :published_by_membership_id)
    add_foreign_key :jrc_service_desk_notification_policy_versions, :inboxes,
                    column: %i[account_id inbox_id], primary_key: %i[account_id id], name: 'jrc_sd_notification_policy_inbox_fk'
  end

  def create_ola_clocks
    create_table :jrc_service_desk_ola_clocks do |table|
      ola_clocks_columns(table)
      table.boolean :pause_waiting, null: false
      ola_policy_columns(table)
      table.timestamps
    end
    scoped_ticket_keys(:jrc_service_desk_ola_clocks)
    add_foreign_key :jrc_service_desk_ola_clocks, :jrc_service_desk_queues,
                    column: %i[account_id unit_id queue_id], primary_key: %i[account_id unit_id id], name: 'jrc_sd_ola_queue_fk'
    add_foreign_key :jrc_service_desk_ola_clocks, :jrc_service_desk_sla_snapshots,
                    column: %i[account_id unit_id ticket_id sla_snapshot_id], primary_key: %i[account_id unit_id ticket_id id],
                    name: 'jrc_sd_ola_snapshot_fk'
    add_index :jrc_service_desk_ola_clocks, %i[account_id unit_id ticket_id], unique: true,
                                                                              where: "state IN ('running','paused')", name: 'jrc_sd_ola_active_unique'
  end

  def ticket_columns(table)
    table.bigint :account_id, null: false
    table.bigint :unit_id, null: false
    table.bigint :ticket_id, null: false
  end

  def scoped_ticket_keys(table)
    add_index table, %i[account_id unit_id ticket_id id], unique: true, name: "#{table.to_s.delete_prefix('jrc_service_desk_')}_scope_ref"
    add_foreign_key table, :jrc_service_desk_tickets, column: %i[account_id unit_id ticket_id],
                                                      primary_key: %i[account_id unit_id id],
                                                      name: "#{table.to_s.delete_prefix('jrc_service_desk_')}_ticket_fk"
  end

  def membership_fk(table, column)
    name = "#{table.to_s.delete_prefix('jrc_service_desk_')}_#{column.to_s.delete_suffix('_membership_id')}_fk"
    add_foreign_key table, :jrc_service_desk_unit_memberships, column: [:account_id, :unit_id, column],
                                                               primary_key: %i[account_id unit_id id],
                                                               name: name
  end

  def scoped_team_fk(table)
    add_foreign_key table, :teams, column: %i[account_id audience_team_id], primary_key: %i[account_id id],
                                   name: "#{table.to_s.delete_prefix('jrc_service_desk_')}_audience_team_fk"
  end
end
