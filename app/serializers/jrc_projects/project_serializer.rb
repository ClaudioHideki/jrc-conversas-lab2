module JrcProjects
  class ProjectSerializer
    def self.one(project, account_user:, details: false, task_counts: nil)
      data = project.as_json(only: %i[id key name description status visibility owner_id contact_id starts_on due_on completed_at acceptance_notes lock_version created_at updated_at])
      data['priority'] = project.priority
      data['owner'] = project.owner.as_json(only: %i[id name])
      data['contact'] = project.contact&.as_json(only: %i[id name email])
      data['capabilities'] = Authorization.capabilities(account_user, project)
      counts = task_counts || { total: project.tasks.count, completed: project.tasks.where(status: 'completed').count }
      data['tasks_total'] = counts[:total]
      data['tasks_completed'] = counts[:completed]
      data['progress'] = data['tasks_total'].zero? ? 0 : (data['tasks_completed'] * 100.0 / data['tasks_total']).round
      if details
        data['contact_locked'] = project.contact_locked?
        data['columns'] = project.board_columns.order(:board_id, :position, :id).as_json(only: %i[id board_id name status_key position wip_limit])
        data['members'] = project.project_members.where(account_id: project.account_id, project_id: project.id).includes(:user).map { |m| m.as_json(only: %i[id user_id role allocation_percent], include: { user: { only: %i[id name] } }) }
        data['phases'] = project.phases.where(account_id: project.account_id, project_id: project.id).order(:id).as_json(only: %i[id name])
        data['overview'] = overview(project)
        financial = data['capabilities'].include?('projects.budget.view')
        data['budget'] = Reporting::FinancialProjection.call(project: project) if financial
        data['recent_activity'] = recent_activity(project, financial: financial, account_user: account_user)
      end
      data
    end

    def self.overview(project)
      tasks = project.tasks.where(account_id: project.account_id, project_id: project.id)
      time = project.time_entries.where(account_id: project.account_id, project_id: project.id)
      {
        overdue_tasks: tasks.where('due_on < ?', Date.current).where.not(status: %w[completed canceled]).count,
        team_size: project.project_members.where(account_id: project.account_id, project_id: project.id).count,
        estimated_minutes: tasks.sum(:estimated_minutes),
        worked_minutes: time.where.not(status: 'rejected').sum(:minutes),
        approved_minutes: time.where(status: 'approved').sum(:minutes),
        upcoming_milestones: project.milestones.where(account_id: project.account_id, project_id: project.id, status: 'open')
                                    .where.not(due_on: nil).order(:due_on, :id).limit(5).as_json(only: %i[id name due_on status phase_id])
      }
    end

    def self.recent_activity(project, financial:, account_user:)
      scope = AuditEvent.where(account_id: project.account_id)
      events = scope.where(auditable_type: 'JrcProjects::Project', auditable_id: project.id)
      resources = {
        'JrcProjects::Task' => project.tasks, 'JrcProjects::Milestone' => project.milestones,
        'JrcProjects::ProjectMember' => project.project_members, 'JrcProjects::TimeEntry' => project.time_entries
      }
      resources.each do |type, records|
        events = events.or(scope.where(auditable_type: type, auditable_id: records.where(account_id: project.account_id).select(:id)))
      end
      # Deleted resources are still represented by their original audit snapshots.
      snapshots = scope.where(auditable_type: resources.keys)
                       .where("after_data ->> 'project_id' = :id OR before_data ->> 'project_id' = :id", id: project.id.to_s)
      events = events.or(snapshots)
      events = events.where.not(action: 'projects.budget.updated') unless financial
      events.includes(:actor).order(created_at: :desc, id: :desc).limit(15).filter_map do |event|
        ids = [event.before_data, event.after_data].flat_map { |data| [data['ticket_id'], data.dig('origin', 'ticket_id')] }.compact
        next unless ids.all? { |id| JrcOperations::Access.tickets(account_user).exists?(id: id) }
        # Never expose raw snapshots: time/budget snapshots can contain financial values.
        event.as_json(only: %i[id action auditable_type auditable_id created_at], include: { actor: { only: %i[id name] } })
      end
    end
  end
end
