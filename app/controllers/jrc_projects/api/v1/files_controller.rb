module JrcProjects
  module Api
    module V1
      class FilesController < BaseController
        def index
          project = scoped_project
          record = params[:task_id].present? ? scoped_tasks(project).find(params[:task_id]) : project
          authorize_capability!(record.is_a?(Task) ? 'projects.task.view' : 'projects.project.view', project: project, record: record)
          render json: { data: serialize_files(record) }
        end
        def create
          project = scoped_project
          record = params[:task_id].present? ? scoped_tasks(project).find(params[:task_id]) : project
          files = Array(params[:files])
          if files.empty? || files.length > 10 || files.any? { |file| !file.is_a?(ActionDispatch::Http::UploadedFile) || file.size > 20.megabytes }
            raise ArgumentError, 'Envie de 1 a 10 arquivos de ate 20 MB.'
          end
          project.with_lock do
            ensure_project_editable!(project) if record.is_a?(Task)
            record.reload
            authorize_capability!(record.is_a?(Task) ? 'projects.task.update' : 'projects.project.update', project: project, record: record)
            before_ids = record.attachments.attachments.ids
            record.attachments.attach(files)
            raise ActiveRecord::RecordInvalid.new(record) if record.errors.any?

            record.reload
            added_ids = record.attachments.attachments.ids - before_ids
            if added_ids.any?
              AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.attachment.added', auditable: record,
                                 after_data: { attachment_ids: added_ids }, correlation_id: correlation_id)
            end
            render json: { data: serialize_files(record) }
          end
        end
        def destroy
          project = scoped_project
          record = params[:task_id].present? ? scoped_tasks(project).find(params[:task_id]) : project
          project.with_lock do
            ensure_project_editable!(project) if record.is_a?(Task)
            record.reload
            authorize_capability!(record.is_a?(Task) ? 'projects.task.update' : 'projects.project.update', project: project, record: record)
            file = record.attachments.attachments.find(params[:id])
            before = { attachment_id: file.id, filename: file.filename.to_s }
            file.purge_later
            AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.attachment.removed', auditable: record,
                               before_data: before, correlation_id: correlation_id)
          end
          head :no_content
        end
        private
        def serialize_files(record)
          files = record.attachments.attachments.includes(:blob).to_a
          uploaders = {}
          AuditEvent.where(account_id: Current.account.id, auditable_type: record.class.name, auditable_id: record.id,
                           action: 'projects.attachment.added').includes(:actor).order(:created_at, :id).each do |event|
            Array(event.after_data['attachment_ids']).each do |id|
              uploaders[id.to_i] ||= event.actor&.as_json(only: %i[id name])
            end
          end
          files.map do |file|
            { id: file.id, name: file.filename.to_s, created_at: file.created_at, byte_size: file.blob.byte_size,
              uploaded_by: uploaders[file.id],
              url: Rails.application.routes.url_helpers.rails_blob_path(file.blob, only_path: true),
              download_url: Rails.application.routes.url_helpers.rails_blob_path(file.blob, disposition: 'attachment', only_path: true) }
          end
        end
      end
    end
  end
end
