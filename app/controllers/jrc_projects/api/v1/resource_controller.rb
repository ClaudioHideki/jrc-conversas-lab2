module JrcProjects
  module Api
    module V1
      class ResourceController < BaseController
        class_attribute :catalog_model, :required_capability, :permitted_attributes
        def index
          project = resource_project
          authorize_read!(project)
          records, meta = pagination(scope_for(project).order(created_at: :desc))
          render json: { data: records, meta: meta }
        end
        def show
          project = resource_project
          authorize_read!(project)
          render json: { data: scope_for(project).find(params[:id]) }
        end
        def create
          project = resource_project
          with_resource_lock(project) do
            authorize_write!(project)
            values = resource_params.merge(account: Current.account)
            values[:project] = project if project
            record = catalog_model.new(values)
            validate_context!(record, project)
            record.save!
            audit_change!(record, 'created', after: record.attributes)
            render json: { data: record }, status: :created
          end
        end
        def update
          project = resource_project
          with_resource_lock(project) do
            authorize_write!(project)
            record = scope_for(project).find(params[:id])
            raise ArgumentError, 'O proprietario nao pode ser alterado por esta tela.' if record.is_a?(ProjectMember) && record.user_id == project.owner_id

            before = record.attributes
            record.assign_attributes(resource_params)
            validate_context!(record, project)
            record.save!
            if record.saved_changes.any?
              action = record.is_a?(Milestone) && record.saved_change_to_status? && record.status == 'completed' ? 'completed' : 'updated'
              audit_change!(record, action, before: before, after: record.attributes)
            end
            render json: { data: record }
          end
        end
        def destroy
          project = resource_project
          with_resource_lock(project) do
            authorize_write!(project)
            record = scope_for(project).find(params[:id])
            raise ArgumentError, 'O proprietario nao pode ser removido.' if record.is_a?(ProjectMember) && record.user_id == project.owner_id
            if record.is_a?(ProjectMember) && scoped_tasks(project).where(assignee_id: record.user_id).exists?
              raise ArgumentError, 'Reatribua as tarefas deste participante antes de remove-lo.'
            end
            before = record.attributes
            record.destroy!
            audit_change!(record, 'deleted', before: before)
          end
          head :no_content
        end
        private
        def with_resource_lock(project, &block)
          project ? project.with_lock(&block) : catalog_model.transaction(&block)
        end
        def audit_change!(record, action, before: {}, after: {})
          return unless record.is_a?(Milestone) || record.is_a?(ProjectMember)

          resource = record.is_a?(Milestone) ? 'milestone' : 'member'
          AuditEvent.record!(account: Current.account, actor: Current.user, action: "projects.#{resource}.#{action}", auditable: record,
                             before_data: before, after_data: after, correlation_id: correlation_id)
        end
        def resource_project
          params[:project_id].present? ? scoped_project : nil
        end
        def authorize_read!(project)
          authorize_capability!('projects.project.view', project: project)
        end
        def authorize_write!(project)
          if project
            authorize_capability!(required_capability, project: project)
            if catalog_model != ProjectMember && %w[completed canceled].include?(project.status)
              raise ArgumentError, 'Reabra o projeto antes de alterar o planejamento.'
            end
          else
            raise Pundit::NotAuthorizedError unless JrcOperations::Access.admin?(Current.account_user)
          end
        end
        def scope_for(project)
          scope = catalog_model.where(account_id: Current.account.id)
          project ? scope.where(project_id: project.id) : scope
        end
        def resource_params
          params.require(:record).permit(*permitted_attributes)
        end
        def validate_context!(record, project)
          if record.is_a?(ProjectMember)
            Current.account.users.find(record.user_id)
            raise ArgumentError, 'Use gerente, membro, colaborador ou observador.' if record.role == 'owner'
            if record.persisted? && record.will_save_change_to_user_id? && scoped_tasks(project).where(assignee_id: record.user_id_in_database).exists?
              raise ArgumentError, 'Reatribua as tarefas antes de trocar o participante.'
            end
          end
          if record.respond_to?(:phase_id) && record.phase_id.present?
            project.phases.where(account_id: Current.account.id, project_id: project.id).find(record.phase_id)
          end
          if record.is_a?(ProjectTemplate)
            raise ArgumentError, 'O modelo deve conter uma definicao valida.' unless record.definition.is_a?(Hash)
          end
        end
      end
    end
  end
end
