# frozen_string_literal: true

# Unlinking retains the native resource. A later explicit deletion in its owning
# module only removes the auxiliary relation; immutable case journal entries remain.
# No task, article, case, ticket or approval is deleted by a Service Desk command.
class PreserveNativeCaseResourceDeletion < ActiveRecord::Migration[7.1]
  def up
    replace_targets(:cascade)
  end

  def down
    replace_targets(nil)
  end

  private

  def replace_targets(action)
    links = :jrc_service_desk_case_resource_links
    remove_foreign_key links, name: 'jrc_sd_case_resource_task'
    add_foreign_key links, :jrc_projects_tasks, column: [:account_id, :project_id, :task_id],
                                                primary_key: [:account_id, :project_id, :id], name: 'jrc_sd_case_resource_task', on_delete: action
    remove_foreign_key links, name: 'jrc_sd_case_resource_article'
    add_foreign_key links, :articles, column: [:account_id, :article_id], primary_key: [:account_id, :id],
                                      name: 'jrc_sd_case_resource_article', on_delete: action
  end
end
