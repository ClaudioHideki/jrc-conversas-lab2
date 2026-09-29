module JrcProjects
  module Api
    module V1
      class PlanningController < BaseController
        def critical_path
          project = scoped_project
          render json: { data: Planning::CriticalPath.call(project: project) }
        end
        def dependencies
          project = scoped_project
          edges = TaskDependency.where(account_id: Current.account.id, predecessor_id: scoped_tasks(project).select(:id), successor_id: scoped_tasks(project).select(:id))
          render json: { data: edges.as_json(only: %i[id predecessor_id successor_id kind]) }
        end
        def dependency
          project = scoped_project
          authorize_capability!('projects.project.update', project: project)
          project.with_lock do
            ensure_project_editable!(project)
            predecessor = scoped_tasks(project).find(params.require(:predecessor_id))
            successor = scoped_tasks(project).find(params.require(:successor_id))
            edge = Planning::DependencyGraph.add!(predecessor: predecessor, successor: successor, kind: params[:kind].presence || 'finish_to_start')
            if edge.previously_new_record?
              AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.task.dependency_added', auditable: successor,
                                 after_data: edge.attributes, correlation_id: correlation_id)
            end
            render json: { data: edge }, status: :created
          end
        end
        def remove_dependency
          project = scoped_project
          authorize_capability!('projects.project.update', project: project)
          project.with_lock do
            ensure_project_editable!(project)
            edge = TaskDependency.where(account_id: Current.account.id, predecessor_id: scoped_tasks(project).select(:id),
                                        successor_id: scoped_tasks(project).select(:id)).find(params[:id])
            before = edge.attributes
            successor = edge.successor
            edge.destroy!
            AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.task.dependency_removed', auditable: successor,
                               before_data: before, correlation_id: correlation_id)
          end
          head :no_content
        end
      end
    end
  end
end
