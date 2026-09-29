module JrcProjects
  module Api
    module V1
      class ProjectsController < BaseController
        def index
          scope = JrcOperations::Access.projects(Current.account_user).includes(:owner, :contact).order(updated_at: :desc)
          scope = scope.where(status: params[:status]) if params[:status].present?
          if params[:priority].present?
            raise ArgumentError, 'Prioridade invalida.' unless Project::PRIORITIES.include?(params[:priority])

            scope = scope.where("COALESCE(NULLIF(jrc_projects_projects.settings ->> 'priority', ''), 'medium') = ?", params[:priority])
          end
          scope = scope.where('jrc_projects_projects.name ILIKE ?', "%#{Project.sanitize_sql_like(params[:q].to_s)}%") if params[:q].present?
          records, meta = pagination(scope)
          project_ids = records.map(&:id)
          total_by_project = Task.where(account_id: Current.account.id, project_id: project_ids).group(:project_id).count
          completed_by_project = Task.where(account_id: Current.account.id, project_id: project_ids, status: 'completed').group(:project_id).count
          task_counts = project_ids.to_h { |project_id| [project_id, { total: total_by_project.fetch(project_id, 0), completed: completed_by_project.fetch(project_id, 0) }] }
          render json: { data: records.map { |project| ProjectSerializer.one(project, account_user: Current.account_user, task_counts: task_counts[project.id]) }, meta: meta }
        end
        def show
          project = scoped_project
          render json: { data: ProjectSerializer.one(project, account_user: Current.account_user, details: true) }
        end
        def create
          template = ProjectTemplate.where(account_id: Current.account.id, active: true).find(params[:template_id]) if params[:template_id].present?
          project = Projects::Create.call(account: Current.account, actor: Current.user, attributes: project_params.to_h, template: template, idempotency_key: request.headers['Idempotency-Key'], origin: params.permit(:deal_id, :ticket_id, :conversation_display_id).to_h, correlation_id: correlation_id)
          render json: { data: ProjectSerializer.one(project, account_user: Current.account_user, details: true) }, status: :created
        end
        def update
          project = Projects::Update.call(
            account: Current.account, actor: Current.user, project: scoped_project,
            attributes: params.require(:project).permit(*Projects::Update::FIELDS, :lock_version).to_h,
            correlation_id: correlation_id
          )
          render json: { data: ProjectSerializer.one(project, account_user: Current.account_user, details: true) }
        end
        private
        def project_params
          params.require(:project).permit(:key, :name, :description, :visibility, :contact_id, :starts_on, :due_on, :priority)
        end
      end
    end
  end
end
