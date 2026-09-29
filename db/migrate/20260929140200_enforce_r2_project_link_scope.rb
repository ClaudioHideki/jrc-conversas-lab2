class EnforceR2ProjectLinkScope < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_operations_links, :ticket_unit_id, :bigint
    add_index :jrc_projects_projects, [:account_id, :id], unique: true, name: 'idx_projects_account_identity'
    add_index :jrc_projects_tasks, [:account_id, :project_id, :id], unique: true, name: 'idx_project_tasks_scope_identity'
    add_foreign_key :jrc_operations_links, :jrc_projects_projects,
      column: [:account_id, :project_id], primary_key: [:account_id, :id], name: 'fk_project_links_account'
    add_foreign_key :jrc_operations_links, :jrc_service_desk_tickets,
      column: [:account_id, :ticket_unit_id, :ticket_id], primary_key: [:account_id, :unit_id, :id], name: 'fk_project_links_r2_unit'
    add_foreign_key :jrc_operations_links, :jrc_projects_tasks,
      column: [:account_id, :project_id, :task_id], primary_key: [:account_id, :project_id, :id], name: 'fk_project_links_task_scope'
    add_check_constraint :jrc_operations_links,
      'num_nonnulls(ticket_id, conversation_id, crm_deal_id) = 1 AND (task_id IS NULL OR ticket_id IS NOT NULL) AND ((ticket_id IS NULL) = (ticket_unit_id IS NULL))',
      name: 'jrc_project_link_shape'
  end
end
