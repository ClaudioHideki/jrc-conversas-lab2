class CreateR2ProjectLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_operations_links do |t|
      t.references :account, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :ticket, foreign_key: { to_table: :jrc_service_desk_tickets }
      t.references :project, null: false, foreign_key: { to_table: :jrc_projects_projects }
      t.references :task, foreign_key: { to_table: :jrc_projects_tasks }
      t.references :conversation, foreign_key: true
      t.references :crm_deal, foreign_key: { to_table: :jrc_crm_deals }
      t.timestamps
    end
    add_index :jrc_operations_links, [:account_id, :project_id, :ticket_id], unique: true, where: 'task_id IS NULL', name: 'idx_jrc_ops_project_ticket'
    add_index :jrc_operations_links, [:account_id, :project_id, :ticket_id, :task_id], unique: true, where: 'task_id IS NOT NULL', name: 'idx_jrc_ops_project_ticket_task'
    add_index :jrc_operations_links, [:account_id, :project_id, :crm_deal_id], unique: true, name: 'idx_jrc_ops_project_deal'
    add_index :jrc_operations_links, [:account_id, :project_id, :conversation_id], unique: true, name: 'idx_jrc_ops_project_conversation'
  end
end
