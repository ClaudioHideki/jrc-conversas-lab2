class AddRichTaskComments < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_projects_task_comments, :content_format, :string, default: 'plain_text', null: false
    add_column :jrc_projects_task_comments, :request_key, :string
    add_column :jrc_projects_task_comments, :request_digest, :string
    add_index :jrc_projects_task_comments, [:account_id, :task_id, :user_id, :request_key], unique: true,
              where: 'request_key IS NOT NULL', name: 'idx_project_comment_request'
  end
end
