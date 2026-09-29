module JrcProjects
  module Tasks
    class Move
      def self.call(task:, actor:, column:, before_task_id: nil, lock_version:, correlation_id: nil)
        raise ActiveRecord::RecordNotFound unless task.account_id == column.account_id && task.project_id == column.board.project_id

        project = task.project
        project.with_lock do
          task.reload
          column.reload
          membership = task.account.account_users.find_by!(user_id: actor.id)
          unless Authorization.allowed?(account_user: membership, capability: 'projects.task.move', project: project, record: task)
            raise Pundit::NotAuthorizedError
          end
          raise ArgumentError, 'Reabra o projeto antes de alterar tarefas.' if %w[completed canceled].include?(project.status)
          raise ActiveRecord::StaleObjectError.new(task, 'move') if lock_version.nil? || task.lock_version != Integer(lock_version)

          same_column = task.board_column_id == column.id && task.status == column.status_key
          next task if same_column && (before_task_id.blank? || before_task_id.to_s == task.id.to_s)

          siblings = column.tasks.where(account_id: task.account_id, project_id: task.project_id).order(:position, :id).to_a
          original_order = siblings.map(&:id)
          siblings.reject! { |sibling| sibling.id == task.id }
          insertion = before_task_id.present? ? siblings.index { |sibling| sibling.id == Integer(before_task_id) } : siblings.length
          raise ArgumentError, 'Tarefa de referencia nao esta na coluna de destino.' if insertion.nil?

          siblings.insert(insertion, task)
          next task if same_column && siblings.map(&:id) == original_order

          if column.wip_limit && column.tasks.where.not(id: task.id).count >= column.wip_limit
            raise Errors::WipLimit, 'Limite de tarefas desta coluna atingido.'
          end
          if column.status_key == 'completed' && task.incoming_dependencies.where(account_id: task.account_id)
                                                    .joins(:predecessor).where.not(jrc_projects_tasks: { status: %w[completed canceled] }).exists?
            raise ArgumentError, 'Conclua ou cancele as tarefas predecessoras primeiro.'
          end
          before = task.attributes.slice('board_column_id', 'status', 'position')
          # The project lock serializes moves, WIP checks and position changes.
          siblings.each_with_index do |sibling, index|
            if sibling.id == task.id
              sibling.update!(board_column: column, status: column.status_key, position: (index + 1) * 1024)
            elsif sibling.position != (index + 1) * 1024
              sibling.update!(position: (index + 1) * 1024)
            end
          end
          after = task.attributes.slice('board_column_id', 'status', 'position')
          if before != after
            AuditEvent.record!(account: task.account, actor: actor, action: 'projects.task.moved', auditable: task,
                               before_data: before, after_data: after, correlation_id: correlation_id)
          end
          task
        end
      end
    end
  end
end
