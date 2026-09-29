module JrcProjects::Api::V1
  class CommentsController < BaseController
    def index
      project = scoped_project
      task = scoped_tasks(project).find(params[:task_id])
      authorize_capability!('projects.task.view', project: project, record: task)
      records, meta = pagination(task.task_comments.where(account_id: Current.account.id).includes(:user).order(:created_at, :id))
      render json: { data: records.as_json(include: { user: { only: %i[id name] } }), meta: meta }
    end
    def create
      project = scoped_project
      task = scoped_tasks(project).find(params[:task_id])
      project.with_lock do
        ensure_project_editable!(project)
        task.reload
        authorize_capability!('projects.task.update', project: project, record: task)
        record = task.task_comments.create!(account: Current.account, user: Current.user, body: params.require(:comment).require(:body))
        JrcProjects::AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.task.comment_added', auditable: task,
                           after_data: { comment_id: record.id }, correlation_id: correlation_id)
        render json: { data: record }, status: :created
      end
    end
  end
end
