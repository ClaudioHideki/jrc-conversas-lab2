# frozen_string_literal: true

module JrcServiceDeskV2WorkSchema
  private

  def create_tasks
    create_table :jrc_service_desk_ticket_tasks do |table|
      tasks_columns(table)
      table.timestamps
    end
    scoped_ticket_keys(:jrc_service_desk_ticket_tasks)
    membership_fk(:jrc_service_desk_ticket_tasks, :created_by_membership_id)
    membership_fk(:jrc_service_desk_ticket_tasks, :assignee_membership_id)
    scoped_team_fk(:jrc_service_desk_ticket_tasks)
    constrain_tasks
  end

  def constrain_tasks
    add_index :jrc_service_desk_ticket_tasks,
              %i[account_id unit_id ticket_id created_by_membership_id idempotency_key],
              unique: true,
              name: 'jrc_sd_task_request_unique'
    add_check_constraint :jrc_service_desk_ticket_tasks,
                         "visibility IN ('internal','technical_team','customer','public_without_notification') AND btrim(title) <> ''",
                         name: 'jrc_sd_task_visibility'
    add_check_constraint :jrc_service_desk_ticket_tasks,
                         "(visibility = 'technical_team') = (audience_team_id IS NOT NULL)", name: 'jrc_sd_task_team_audience'
  end

  def tasks_columns(table)
    ticket_columns(table)
    table.bigint :created_by_membership_id, null: false
    table.bigint :assignee_membership_id
    table.string :title, null: false, limit: 255
    table.text :description
    table.datetime :due_at
    table.string :priority, null: false, default: 'normal'
    table.string :status, null: false, default: 'open'
    table.string :visibility, null: false, default: 'internal', limit: 40
    table.bigint :audience_team_id
    table.jsonb :checklist, null: false, default: []
    table.datetime :completed_at
    table.string :idempotency_key, null: false, limit: 120
    table.string :request_fingerprint, null: false, limit: 64
    table.integer :lock_version, null: false, default: 0
  end

  def create_approvals
    create_table :jrc_service_desk_ticket_approvals do |table|
      approvals_columns(table)
      table.timestamps
    end
    scoped_ticket_keys(:jrc_service_desk_ticket_approvals)
    membership_fk(:jrc_service_desk_ticket_approvals, :requested_by_membership_id)
    membership_fk(:jrc_service_desk_ticket_approvals, :approver_membership_id)
    add_index :jrc_service_desk_ticket_approvals,
              %i[account_id unit_id ticket_id requested_by_membership_id idempotency_key],
              unique: true,
              name: 'jrc_sd_approval_request_unique'
  end

  def approvals_columns(table)
    ticket_columns(table)
    table.bigint :requested_by_membership_id, null: false
    table.bigint :approver_membership_id, null: false
    table.string :title, null: false, limit: 255
    table.text :description
    table.datetime :due_at, null: false
    table.string :status, null: false, default: 'pending'
    table.text :comment
    table.datetime :decided_at
    table.string :idempotency_key, null: false, limit: 120
    table.string :request_fingerprint, null: false, limit: 64
    table.integer :lock_version, null: false, default: 0
  end
end
