# frozen_string_literal: true

class AddServiceDeskOperationalRuleVersions < ActiveRecord::Migration[7.1]
  def up
    create_table :jrc_service_desk_operational_rule_versions do |table|
      table.bigint :account_id, null: false
      table.bigint :unit_id, null: false
      table.bigint :published_by_membership_id, null: false
      table.string :kind, null: false
      table.integer :version, null: false
      table.boolean :enabled, null: false, default: false
      table.jsonb :definition, null: false
      table.string :digest, null: false
      table.datetime :created_at, null: false
    end
    add_index :jrc_service_desk_operational_rule_versions, %i[account_id unit_id kind version],
              unique: true, name: 'jrc_sd_rule_version_unique'
    add_index :jrc_service_desk_operational_rule_versions, %i[account_id unit_id id],
              unique: true, name: 'jrc_sd_rule_scope_unique'
    add_foreign_key :jrc_service_desk_operational_rule_versions, :jrc_service_desk_units,
                    column: %i[account_id unit_id], primary_key: %i[account_id id], name: 'jrc_sd_rule_unit_fk'
    add_foreign_key :jrc_service_desk_operational_rule_versions, :jrc_service_desk_unit_memberships,
                    column: %i[account_id unit_id published_by_membership_id], primary_key: %i[account_id unit_id id],
                    name: 'jrc_sd_rule_publisher_fk'
    add_check_constraint :jrc_service_desk_operational_rule_versions, 'version > 0', name: 'jrc_sd_rule_positive_version'
    add_check_constraint :jrc_service_desk_operational_rule_versions,
                         "kind IN ('routing','priority_matrix','sla_selection','approval_deadline','recurrence')",
                         name: 'jrc_sd_rule_finite_kind'
    add_check_constraint :jrc_service_desk_operational_rule_versions,
                         "jsonb_typeof(definition) = 'object' AND digest ~ '^[a-f0-9]{64}$'", name: 'jrc_sd_rule_definition'
    add_column :jrc_service_desk_ticket_approvals, :deadline_rule_version_id, :bigint
    add_foreign_key :jrc_service_desk_ticket_approvals, :jrc_service_desk_operational_rule_versions,
                    column: %i[account_id unit_id deadline_rule_version_id], primary_key: %i[account_id unit_id id],
                    name: 'jrc_sd_approval_deadline_rule_fk'
    add_column :jrc_service_desk_tickets, :impact_code, :string
    add_column :jrc_service_desk_tickets, :urgency_code, :string
    add_check_constraint :jrc_service_desk_tickets,
                         '(impact_code IS NULL AND urgency_code IS NULL) OR ' \
                         '(impact_code IS NOT NULL AND urgency_code IS NOT NULL AND ' \
                         "impact_code ~ '^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$' AND " \
                         "urgency_code ~ '^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$')",
                         name: 'jrc_sd_explicit_impact_urgency'
    add_index :jrc_service_desk_ticket_approvals, %i[due_at id], where: "status = 'pending' AND deadline_rule_version_id IS NOT NULL",
                                                                 name: 'jrc_sd_pending_deadline_scan'
    create_table :jrc_service_desk_rule_executions do |table|
      table.bigint :account_id, null: false
      table.bigint :unit_id, null: false
      table.bigint :ticket_id, null: false
      table.bigint :rule_version_id, null: false
      table.string :operation_key, null: false
      table.jsonb :result, null: false, default: {}
      table.datetime :created_at, null: false
    end
    add_index :jrc_service_desk_rule_executions, %i[account_id unit_id operation_key], unique: true, name: 'jrc_sd_rule_once'
    add_foreign_key :jrc_service_desk_rule_executions, :jrc_service_desk_tickets,
                    column: %i[account_id unit_id ticket_id], primary_key: %i[account_id unit_id id], name: 'jrc_sd_rule_ticket_fk'
    add_foreign_key :jrc_service_desk_rule_executions, :jrc_service_desk_operational_rule_versions,
                    column: %i[account_id unit_id rule_version_id], primary_key: %i[account_id unit_id id], name: 'jrc_sd_execution_rule_fk'
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Preserve operational rule versions, approval executions and ticket history; use a reviewed forward recovery'
  end
end
