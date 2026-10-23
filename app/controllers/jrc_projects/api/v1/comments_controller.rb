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

    def update
      change_comment! do |record, task|
        before = record.attributes.slice('id', 'body', 'user_id')
        record.update!(body: params.require(:comment).require(:body))
        JrcProjects::AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.task.comment_updated', auditable: task,
                                       before_data: before, after_data: record.attributes.slice('id', 'body', 'user_id'), correlation_id: correlation_id)
        render json: { data: record }
      end
    end

    def destroy
      change_comment! do |record, task|
        before = record.attributes.slice('id', 'body', 'user_id')
        record.destroy!
        JrcProjects::AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.task.comment_deleted', auditable: task,
                                       before_data: before, correlation_id: correlation_id)
        head :no_content
      end
    end

    private

    def change_comment!
      project = scoped_project
      project.with_lock do
        ensure_project_editable!(project)
        task = scoped_tasks(project).find(params[:task_id])
        authorize_capability!('projects.task.update', project: project, record: task)
        record = task.task_comments.where(account_id: Current.account.id).find(params[:id])
        manager = JrcProjects::Authorization.allowed?(account_user: Current.account_user, capability: 'projects.project.update', project: project)
        raise Pundit::NotAuthorizedError unless record.user_id == Current.user.id || manager

        yield record, task
      end
    end
  end
end
