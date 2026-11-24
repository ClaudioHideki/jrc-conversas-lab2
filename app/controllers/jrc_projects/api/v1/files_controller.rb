module JrcProjects
  module Api
    module V1
      class FilesController < BaseController
        def index
          render json: { data: serialize_files(readable_record) }
        end

        def show
          file = readable_record.attachments.attachments.find(params[:id])
          blob = file.blob
          bytes = read_file(blob)
          disposition = params[:disposition] == 'attachment' ? 'attachment' : 'inline'
          response.headers['Cache-Control'] = 'private, no-store'
          response.headers['X-Content-Type-Options'] = 'nosniff'
          send_data bytes, filename: blob.filename.to_s, type: blob.content_type_for_serving,
                           disposition: blob.forced_disposition_for_serving || disposition
        rescue JrcServiceDesk::AttachmentScanError
          head :not_found
        rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError
          render json: { error: { code: 'FILE_UNAVAILABLE', message: 'O arquivo está indisponível no armazenamento.' } }, status: :gone
        rescue Aws::S3::Errors::ServiceError
          render json: { error: { code: 'STORAGE_UNAVAILABLE', message: 'Não foi possível acessar o armazenamento.' } }, status: :service_unavailable
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

            # Active Storage uploads these files after commit. Reloading here
            # clears its pending attachment changes before that callback runs.
            added_ids = record.attachments.attachments.map(&:id) - before_ids
            if added_ids.any?
              AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.attachment.added', auditable: record,
                                 after_data: { attachment_ids: added_ids }, correlation_id: correlation_id)
            end
          end
          render json: { data: serialize_files(record) }
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

        def readable_record
          project = scoped_project
          authorize_capability!('projects.attachment.view', project: project)
          record = params[:task_id].present? ? scoped_tasks(project).find(params[:task_id]) : project
          authorize_capability!(record.is_a?(Task) ? 'projects.task.view' : 'projects.project.view', project: project, record: record)
          record
        end

        def read_file(blob)
          if blob.metadata.key?(JrcCulture::Files::MARKER) || blob.metadata[JrcServiceDesk::ReportExport::MANAGERIAL_BLOB_MARKER]
            raise ActiveRecord::RecordNotFound
          end

          context = { blob: blob, user: Current.user, account_id: Current.account.id }
          protected_access = JrcServiceDesk::ProtectedBlobAccess.new(**context)
          raise ActiveRecord::RecordNotFound if protected_access.protected? && !protected_access.allowed?

          imported = JrcMigrations::ProtectedBlobAccess.new(**context)
          return imported.download if imported.protected?

          blob.open(&:read)
        end

        def file_path(record, file, **options)
          options = options.merge(account_id: Current.account.id, id: file.id)
          if record.is_a?(Task)
            jrc_projects_project_task_file_path(**options, project_id: record.project_id, task_id: record.id)
          else
            jrc_projects_project_file_path(**options, project_id: record.id)
          end
        end

        def serialize_files(record)
          files = record.attachments_attachments.includes(:blob).to_a
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
              url: file_path(record, file), download_url: file_path(record, file, disposition: 'attachment') }
          end
        end
      end
    end
  end
end
