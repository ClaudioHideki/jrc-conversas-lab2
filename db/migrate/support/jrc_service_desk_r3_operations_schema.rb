# frozen_string_literal: true

module JrcServiceDeskR3OperationsSchema
  def extend_operational_work
    remove_check_constraint :jrc_service_desk_sla_clocks, name: 'jrc_sd_lc_clock_values'
    add_check_constraint :jrc_service_desk_sla_clocks,
                         "kind IN ('first_response','attendance','resolution') AND state IN ('running','paused','completed','stopped') " \
                         'AND budget_seconds > 0 AND elapsed_seconds >= 0', name: 'jrc_sd_lc_clock_values'
    remove_check_constraint :jrc_service_desk_lifecycle_pauses, name: 'jrc_sd_lc_pause_period'
    add_check_constraint :jrc_service_desk_lifecycle_pauses,
                         "jsonb_typeof(clocks) = 'array' AND clocks <@ '[\"first_response\",\"attendance\",\"resolution\"]'::jsonb " \
                         'AND ((ended_at IS NULL) = (ended_by_membership_id IS NULL)) AND (ended_at IS NULL OR ended_at >= started_at)',
                         name: 'jrc_sd_lc_pause_period'
    add_column :jrc_service_desk_queues, :ola_escalation_policy, :jsonb, null: false, default: {}
    add_column :jrc_service_desk_ola_clocks, :escalation_snapshot, :jsonb, null: false, default: {}
    extend_task_progression
    extend_approval_authority
    add_column :jrc_service_desk_incidents, :resource_kind, :string, null: false, default: 'incident'
    add_column :jrc_service_desk_incidents, :owner_membership_id, :bigint
    r3_unit_fk(:jrc_service_desk_incidents, :owner_membership_id, :jrc_service_desk_unit_memberships, 'incident_owner')
    add_check_constraint :jrc_service_desk_incidents, "resource_kind IN ('incident','problem')", name: 'jrc_sd_r3_incident_kind'
  end

  def extend_task_progression
    table = :jrc_service_desk_ticket_tasks
    add_column table, :parent_task_id, :bigint
    add_column table, :completion_policy, :jsonb, null: false, default: {}
    add_column table, :completion_policy_digest, :string, limit: 64
    add_foreign_key table, table, column: %i[account_id unit_id ticket_id parent_task_id], primary_key: %i[account_id unit_id ticket_id id],
                                  name: 'jrc_sd_r3_task_parent_fk'
    add_check_constraint table, 'parent_task_id IS NULL OR parent_task_id <> id', name: 'jrc_sd_r3_task_not_self'
  end

  def extend_approval_authority
    table = :jrc_service_desk_ticket_approvals
    change_column_null table, :approver_membership_id, true
    %i[approver_team_id approver_custom_role_id decided_by_membership_id escalated_by_membership_id].each do |column|
      add_column table, column, :bigint
    end
    add_column table, :approver_role, :string
    add_column table, :history, :jsonb, null: false, default: []
    add_index table, %i[account_id unit_id id], unique: true, name: 'jrc_sd_r3_approval_scope'
    r3_account_fk(table, :approver_team_id, :teams, 'approval_team')
    r3_account_fk(table, :approver_custom_role_id, :custom_roles, 'approval_custom_role') if table_exists?(:custom_roles)
    %i[decided_by_membership_id escalated_by_membership_id].each do |column|
      r3_unit_fk(table, column, :jrc_service_desk_unit_memberships, "approval_#{column}")
    end
    add_check_constraint table, 'num_nonnulls(approver_membership_id, approver_team_id, approver_role, approver_custom_role_id) = 1',
                         name: 'jrc_sd_r3_approval_one_authority'
  end

  def create_operational_resources
    table = :jrc_service_desk_operational_resources
    create_table table do |row|
      operational_resource_columns(row)
      row.timestamps
    end
    add_index table, %i[account_id unit_id id], unique: true, name: 'jrc_sd_r3_resource_scope'
    add_index table, %i[account_id unit_id created_by_membership_id idempotency_key], unique: true, name: 'jrc_sd_r3_resource_request'
    add_index table, %i[account_id unit_id resource_kind code], unique: true, where: 'code IS NOT NULL', name: 'jrc_sd_r3_resource_code'
    r3_account_fk(table, :unit_id, :jrc_service_desk_units, 'resource_unit')
    r3_account_fk(table, :company_id, :companies, 'resource_company')
    %i[owner_membership_id created_by_membership_id].each do |column|
      r3_unit_fk(table, column, :jrc_service_desk_unit_memberships, "resource_#{column}")
    end
    r3_unit_fk(table, :approval_id, :jrc_service_desk_ticket_approvals, 'resource_approval')
    constrain_operational_resources(table)
  end

  def constrain_operational_resources(table)
    add_check_constraint table, "resource_kind IN ('change','asset') AND priority IN ('low','normal','high','critical')",
                         name: 'jrc_sd_r3_resource_values'
    add_check_constraint table,
                         "(resource_kind = 'change' AND state IN ('requested','planned','approved','in_progress','completed','cancelled')) OR " \
                         "(resource_kind = 'asset' AND state IN ('active','inactive','retired'))", name: 'jrc_sd_r3_resource_state'
    add_check_constraint table, 'planned_end_at IS NULL OR planned_start_at IS NOT NULL AND planned_end_at > planned_start_at',
                         name: 'jrc_sd_r3_resource_window'
  end

  def operational_resource_columns(row)
    %i[account_id unit_id created_by_membership_id].each { |column| row.bigint column, null: false }
    %i[owner_membership_id company_id approval_id].each { |column| row.bigint column }
    %i[name resource_kind state priority idempotency_key request_fingerprint].each { |column| row.string column, null: false }
    row.string :code
    row.text :description
    row.datetime :planned_start_at
    row.datetime :planned_end_at
    row.jsonb :details, null: false, default: {}
    row.jsonb :history, null: false, default: []
    row.integer :lock_version, null: false, default: 0
  end

  def create_resource_links
    table = :jrc_service_desk_resource_ticket_links
    create_table table do |row|
      %i[account_id unit_id operational_resource_id ticket_id linked_by_membership_id].each { |column| row.bigint column, null: false }
      row.datetime :created_at, null: false
    end
    add_index table, %i[account_id unit_id operational_resource_id ticket_id], unique: true, name: 'jrc_sd_r3_resource_ticket_unique'
    r3_unit_fk(table, :operational_resource_id, :jrc_service_desk_operational_resources, 'resource_link')
    r3_unit_fk(table, :ticket_id, :jrc_service_desk_tickets, 'resource_ticket')
    r3_unit_fk(table, :linked_by_membership_id, :jrc_service_desk_unit_memberships, 'resource_link_actor')
  end
end
