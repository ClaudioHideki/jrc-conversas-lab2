module JrcProjects
  module Api
    module V1
      class ChecklistItemsController < BaseController
        def create
          project = scoped_project
          task = scoped_tasks(project).find(params[:task_id])
          project.with_lock do
            ensure_project_editable!(project)
            task.reload
            authorize_capability!('projects.task.update', project: project, record: task)
            item = task.checklist_items.create!(params.require(:item).permit(:text, :completed).merge(
              account: Current.account, position: task.checklist_items.count
            ))
            AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.task.checklist_added', auditable: task,
                               after_data: item.attributes, correlation_id: correlation_id)
            render json: { data: item }, status: :created
          end
        end
        def update
          project = scoped_project
          task = scoped_tasks(project).find(params[:task_id])
          project.with_lock do
            ensure_project_editable!(project)
            task.reload
            authorize_capability!('projects.task.update', project: project, record: task)
            item = task.checklist_items.where(account_id: Current.account.id).find(params[:id])
            before = item.attributes
            item.assign_attributes(params.require(:item).permit(:text, :completed))
            if item.changed?
              item.save!
              AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.task.checklist_updated', auditable: task,
                                 before_data: before, after_data: item.attributes, correlation_id: correlation_id)
            end
            render json: { data: item }
          end
        end
        def destroy
          project = scoped_project
          task = scoped_tasks(project).find(params[:task_id])
          project.with_lock do
            ensure_project_editable!(project)
            task.reload
            authorize_capability!('projects.task.update', project: project, record: task)
            item = task.checklist_items.where(account_id: Current.account.id).find(params[:id])
            before = item.attributes
            item.destroy!
            AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.task.checklist_removed', auditable: task,
                               before_data: before, correlation_id: correlation_id)
          end
          head :no_content
        end
      end
    end
  end
end
