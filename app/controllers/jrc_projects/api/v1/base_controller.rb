module JrcProjects
  module Api
    module V1
      class BaseController < JrcOperations::BaseController
        before_action -> { raise Pundit::NotAuthorizedError unless JrcOperations::Access.project_access?(Current.account_user) }
        rescue_from JrcProjects::Errors::DependencyCycle, JrcProjects::Errors::WipLimit do |error|
          render json: { error: { code: 'PLANNING_CONFLICT', message: error.message } }, status: :unprocessable_entity
        end
        private
        def authorize_capability!(capability, project: nil, record: nil)
          raise Pundit::NotAuthorizedError unless Authorization.allowed?(account_user: Current.account_user, capability: capability, project: project, record: record)
        end
        def scoped_project
          JrcOperations::Access.projects(Current.account_user).find(params[:project_id] || params[:id])
        end
        def scoped_tasks(project)
          project.tasks.where(account_id: Current.account.id, project_id: project.id)
        end
        def ensure_project_editable!(project)
          raise ArgumentError, 'Reabra o projeto antes de alterar tarefas ou registrar horas.' if %w[completed canceled].include?(project.status)
        end
      end
    end
  end
end
