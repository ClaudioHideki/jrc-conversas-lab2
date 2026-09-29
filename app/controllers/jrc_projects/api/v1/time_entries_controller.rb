module JrcProjects
  module Api
    module V1
      class TimeEntriesController < BaseController
        def index
          project = scoped_project
          records, meta = pagination(project.time_entries.where(account_id: Current.account.id, project_id: project.id).includes(:user).order(worked_on: :desc, id: :desc))
          render json: { data: records.map { |r| serialize(r, project) }, meta: meta }
        end
        def create
          project = scoped_project
          project.with_lock do
            authorize_capability!('projects.time_entry.create', project: project)
            ensure_project_editable!(project)
            values = params.require(:time_entry).permit(:task_id, :minutes, :worked_on, :notes)
            scoped_tasks(project).find(values[:task_id]) if values[:task_id].present?
            record = project.time_entries.create!(values.merge(account: Current.account, user: Current.user, currency: project.budget&.currency || 'BRL'))
            AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.time_entry.created', auditable: record,
                               after_data: record.attributes, correlation_id: correlation_id)
            render json: { data: serialize(record, project) }, status: :created
          end
        end
        def update
          project = scoped_project
          project.with_lock do
            record = project.time_entries.where(account_id: Current.account.id, project_id: project.id).find(params[:id])
            manager = Authorization.allowed?(account_user: Current.account_user, capability: 'projects.time_entry.manage', project: project)
            raise Pundit::NotAuthorizedError unless manager || (record.user_id == Current.user.id && record.status == 'submitted' &&
              Authorization.allowed?(account_user: Current.account_user, capability: 'projects.time_entry.create', project: project))
            values = params.require(:time_entry).permit(:minutes, :worked_on, :notes)
            if manager
              values[:status] = params[:time_entry][:status] if params[:time_entry].key?(:status)
              if Authorization.allowed?(account_user: Current.account_user, capability: 'projects.budget.manage', project: project) && params[:time_entry].key?(:hourly_cost_cents)
                values[:hourly_cost_cents] = params[:time_entry][:hourly_cost_cents]
              end
            end
            before = record.attributes
            record.update!(values)
            if record.saved_changes.any?
              AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.time_entry.updated', auditable: record,
                                 before_data: before, after_data: record.attributes, correlation_id: correlation_id)
            end
            render json: { data: serialize(record, project) }
          end
        end
        private
        def serialize(record, project)
          data = record.as_json(include: { user: { only: %i[id name] } })
          data.delete('hourly_cost_cents') unless Authorization.allowed?(account_user: Current.account_user, capability: 'projects.budget.view', project: project)
          data
        end
      end
    end
  end
end
