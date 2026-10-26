module JrcProjects::Api::V1
  class CommentsController < BaseController
    def index
      project = scoped_project
      task = scoped_tasks(project).find(params[:task_id])
      authorize_capability!('projects.task.view', project: project, record: task)
      records, meta = pagination(task.task_comments.where(account_id: Current.account.id)
                                    .includes(:user, inline_images_attachments: :blob).order(:created_at, :id))
      render json: { data: records.map { |record| JrcProjects::TaskCommentSerializer.new(record).as_json }, meta: meta }
    end
    def create
      project = scoped_project
      task = scoped_tasks(project).find(params[:task_id])
      project.with_lock do
        ensure_project_editable!(project)
        task.reload
        authorize_capability!('projects.task.update', project: project, record: task)
        record = task.task_comments.new(account: Current.account, user: Current.user)
        content = JrcProjects::CommentContent.new(record: record, parameters: params.require(:comment))
        content.validate!
        request_key = request.headers['Idempotency-Key'].presence
        if request_key && (previous = task.task_comments.find_by(account: Current.account, user: Current.user, request_key: request_key))
          return render json: { error: 'Chave de envio já utilizada para outro conteúdo.' }, status: :conflict unless previous.request_digest == content.digest

          return render json: { data: JrcProjects::TaskCommentSerializer.new(previous).as_json }
        end
        record.assign_attributes(request_key: request_key, request_digest: request_key ? content.digest : nil)
        content.apply!
        JrcProjects::AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.task.comment_added', auditable: task,
                           after_data: { comment_id: record.id }, correlation_id: correlation_id)
        render json: { data: JrcProjects::TaskCommentSerializer.new(record).as_json }, status: :created
      end
    end

    def update
      change_comment! do |record, task|
        before = record.attributes.slice('id', 'body', 'user_id')
        if JrcProjects::CommentContent.new(record: record, parameters: params.require(:comment)).apply!
          JrcProjects::AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.task.comment_updated', auditable: task,
                                         before_data: before, after_data: record.attributes.slice('id', 'body', 'user_id'), correlation_id: correlation_id)
        end
        render json: { data: JrcProjects::TaskCommentSerializer.new(record).as_json }
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

    def image
      project = scoped_project
      task = scoped_tasks(project).find(params[:task_id])
      authorize_capability!('projects.task.view', project: project, record: task)
      record = task.task_comments.where(account_id: Current.account.id).find(params[:id])
      attachment = record.inline_images.attachments.includes(:blob).find(params[:image_id])
      raise ActiveRecord::RecordNotFound unless JrcProjects::CommentContent::IMAGE_TYPES.include?(attachment.content_type)

      response.headers['Cache-Control'] = 'private, no-store'
      response.headers['X-Content-Type-Options'] = 'nosniff'
      response.headers['Content-Security-Policy'] = "default-src 'none'; sandbox"
      send_data attachment.download, type: attachment.content_type, disposition: 'inline', filename: attachment.filename.to_s
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
