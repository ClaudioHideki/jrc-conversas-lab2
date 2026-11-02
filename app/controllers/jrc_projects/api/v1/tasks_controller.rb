module JrcProjects
  module Api
    module V1
      class TasksController < BaseController
        def index
          project = scoped_project
          authorize_capability!('projects.task.view', project: project)
          records, meta = pagination(scoped_tasks(project).includes(:assignee).order(:position, :id))
          minutes = TimeEntry.where(account_id: Current.account.id, project_id: project.id, task_id: records.map(&:id))
                            .where.not(status: 'rejected').group(:task_id).sum(:minutes)
          counts = task_counts(records.map(&:id))
          read_projection = ReadProjection.new(account_user: Current.account_user, projects: [project])
          render json: {
            data: records.map do |task|
              serialize(task, worked_minutes: minutes.fetch(task.id, 0), counts: counts.fetch(task.id), read_projection: read_projection)
            end, meta: meta
          }
        end

        def show
          project = scoped_project
          authorize_capability!('projects.task.view', project: project)
          task = scoped_tasks(project).find(params[:id])
          read_projection = ReadProjection.new(account_user: Current.account_user, projects: [project])
          render json: { data: serialize(task, read_projection: read_projection).merge(
            checklist: task.checklist_items.where(account_id: Current.account.id).order(:position, :id),
            comments: task.task_comments.where(account_id: Current.account.id).includes(:user, inline_images_attachments: :blob)
                          .order(:created_at, :id).last(100).map { |comment| TaskCommentSerializer.new(comment).as_json },
            dependencies: task.incoming_dependencies.where(account_id: Current.account.id, predecessor_id: scoped_tasks(project).select(:id))
                              .as_json(only: %i[id predecessor_id kind]),
            subtasks: task.subtasks.where(account_id: Current.account.id, project_id: project.id).order(:position, :id)
                          .as_json(only: %i[id title status]),
            recent_activity: task_activity(task)
          ) }
        end

        def create
          project = scoped_project
          authorize_capability!('projects.task.create', project: project)
          attributes = params.require(:task).permit(:title, :description, :priority, :assignee_id, :parent_id,
                                                   :board_column_id, :estimated_minutes, :starts_on, :due_on, labels: [])
          task = Tasks::Create.call(account_user: Current.account_user, project: project, attributes: attributes,
                                    correlation_id: correlation_id)
          render json: { data: serialize(task) }, status: :created
        end

        def update
          project = scoped_project
          task = scoped_tasks(project).find(params[:id])
          project.with_lock do
            ensure_project_editable!(project)
            task.reload
            authorize_capability!('projects.task.update', project: project, record: task)
            assert_lock!(task, params.require(:task)[:lock_version])
            before = task.attributes
            task.assign_attributes(task_params(project))
            task.save!
            if task.saved_changes.any?
              AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.task.updated', auditable: task,
                                 before_data: before, after_data: task.attributes, correlation_id: correlation_id)
            end
          end
          render json: { data: serialize(task) }
        end

        def move
          project = scoped_project
          task = scoped_tasks(project).find(params[:id])
          authorize_capability!('projects.task.move', project: project, record: task)
          column = project.board_columns.where(account_id: Current.account.id).find(params.require(:column_id))
          Tasks::Move.call(task: task, actor: Current.user, column: column, lock_version: params[:lock_version],
                           before_task_id: params[:before_task_id], correlation_id: correlation_id)
          render json: { data: serialize(task) }
        end

        def destroy
          project = scoped_project
          task = scoped_tasks(project).find(params[:id])
          authorize_capability!('projects.task.delete', project: project, record: task)
          project.with_lock do
            ensure_project_editable!(project)
            task.reload
            assert_lock!(task, params[:lock_version]) if params.key?(:lock_version)
            before = task.attributes
            task.destroy!
            AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.task.deleted', auditable: task,
                               before_data: before, correlation_id: correlation_id)
          end
          head :no_content
        end

        private

        def task_params(project)
          values = params.require(:task).permit(:title, :description, :priority, :assignee_id, :parent_id,
                                               :estimated_minutes, :starts_on, :due_on, labels: []).to_h.symbolize_keys
          if values.key?(:assignee_id)
            user = Current.account.users.find(values[:assignee_id]) if values[:assignee_id].present?
            project.project_members.where(account_id: Current.account.id, project_id: project.id).find_by!(user_id: user.id) if user
            values[:assignee_id] = user&.id
          end
          if values.key?(:parent_id)
            values[:parent_id] = values[:parent_id].present? ? scoped_tasks(project).find(values[:parent_id]).id : nil
          end
          values
        end

        def task_counts(ids)
          checklist = ChecklistItem.where(account_id: Current.account.id, task_id: ids).group(:task_id, :completed).count
          comments = TaskComment.where(account_id: Current.account.id, task_id: ids).group(:task_id).count
          attachments = ActiveStorage::Attachment.where(record_type: 'JrcProjects::Task', record_id: ids, name: 'attachments').group(:record_id).count
          ids.to_h do |id|
            completed = checklist.fetch([id, true], 0)
            [id, { 'checklist_total' => completed + checklist.fetch([id, false], 0), 'checklist_completed' => completed,
                   'comments_count' => comments.fetch(id, 0), 'attachments_count' => attachments.fetch(id, 0) }]
          end
        end

        def task_activity(task)
          events = AuditEvent.where(account_id: Current.account.id, auditable_type: 'JrcProjects::Task', auditable_id: task.id)
                             .includes(:actor).order(created_at: :desc, id: :desc).limit(20)
          events.filter_map do |event|
            ticket_ids = [event.before_data, event.after_data].flat_map { |data| [data['ticket_id'], data.dig('origin', 'ticket_id')] }.compact
            next unless ticket_ids.all? { |id| JrcOperations::Access.tickets(Current.account_user).exists?(id: id) }

            event.as_json(only: %i[id action created_at], include: { actor: { only: %i[id name] } })
          end
        end

        def serialize(task, worked_minutes: nil, counts: nil, read_projection: nil)
          data = task.as_json(only: %i[id project_id parent_id title description status priority board_column_id assignee_id created_by_id
                                       position estimated_minutes starts_on due_on lock_version created_at updated_at],
                              include: { assignee: { only: %i[id name] } })
          data['labels'] = task.labels
          data.merge!(counts || task_counts([task.id]).fetch(task.id))
          data['worked_minutes'] = worked_minutes || task.time_entries.where(account_id: Current.account.id, project_id: task.project_id)
                                                        .where.not(status: 'rejected').sum(:minutes)
          if read_projection
            data.merge!(read_projection.task_permissions(task))
          else
            data['can_update'] = Authorization.allowed?(account_user: Current.account_user, capability: 'projects.task.update', project: task.project, record: task)
            data['can_move'] = Authorization.allowed?(account_user: Current.account_user, capability: 'projects.task.move', project: task.project, record: task)
            data['can_delete'] = Authorization.allowed?(account_user: Current.account_user, capability: 'projects.task.delete', project: task.project, record: task)
          end
          data
        end
      end
    end
  end
end
