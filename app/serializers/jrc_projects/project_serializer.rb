module JrcProjects
  class ProjectSerializer
    def self.one(project, account_user:, details: false, task_counts: nil, card_counts: nil)
      data = project.as_json(only: %i[id key name description status visibility owner_id contact_id starts_on due_on completed_at acceptance_notes lock_version created_at updated_at])
      if project.account.feature_enabled?('jrc_customer_master') &&
         JrcCustomers::DirectoryPolicy.new(JrcOperations::Access.user_context(account_user), :directory).access?
        data['company_id'] = project.company_id
        company = JrcCustomers::Company.where(account_id: project.account_id).find_by(id: project.company_id)
        data['company'] = company&.as_json(only: %i[id name])
      end
      data['priority'] = project.priority
      data['owner'] = project.owner.as_json(only: %i[id name])
      data['contact'] = project.contact&.as_json(only: %i[id name email])
      data['capabilities'] = Authorization.capabilities(account_user, project)
      counts = task_counts || { total: project.tasks.count, completed: project.tasks.where(status: 'completed').count }
      data['tasks_total'] = counts[:total]
      data['tasks_completed'] = counts[:completed]
      data['progress'] = data['tasks_total'].zero? ? 0 : (data['tasks_completed'] * 100.0 / data['tasks_total']).round
      data.merge!(card_counts || self.card_counts(account_id: project.account_id, project_ids: [project.id]).fetch(project.id))
      if details
        data['contact_locked'] = project.contact_locked?
        data['accepted_by'] = project.accepted_by&.as_json(only: %i[id name])
        data['columns'] = project.board_columns.order(:board_id, :position, :id).as_json(only: %i[id board_id name status_key position wip_limit])
        data['members'] = members(project)
        data['phases'] = project.phases.where(account_id: project.account_id, project_id: project.id).order(:id).as_json(only: %i[id name])
        data['overview'] = overview(project)
        financial = data['capabilities'].include?('projects.budget.view')
        data['budget'] = Reporting::FinancialProjection.call(project: project) if financial
        data['recent_activity'] = recent_activity(project, financial: financial, account_user: account_user)
      end
      data
    end

    def self.card_counts(account_id:, project_ids:)
      members = ProjectMember.where(account_id: account_id, project_id: project_ids).group(:project_id).count
      comments = TaskComment.joins(:task).where(account_id: account_id, jrc_projects_tasks: { account_id: account_id, project_id: project_ids })
                            .group('jrc_projects_tasks.project_id').count
      project_files = ActiveStorage::Attachment.where(record_type: 'JrcProjects::Project', record_id: project_ids, name: 'attachments')
                                               .group(:record_id).count
      task_files = ActiveStorage::Attachment
                   .joins('INNER JOIN jrc_projects_tasks ON jrc_projects_tasks.id = active_storage_attachments.record_id')
                   .where(record_type: 'JrcProjects::Task', name: 'attachments',
                          jrc_projects_tasks: { account_id: account_id, project_id: project_ids })
                   .group('jrc_projects_tasks.project_id').count
      project_ids.to_h do |id|
        [id, { 'members_count' => members.fetch(id, 0), 'comments_count' => comments.fetch(id, 0),
               'attachments_count' => project_files.fetch(id, 0) + task_files.fetch(id, 0) }]
      end
    end

    def self.members(project)
      members = project.project_members.where(account_id: project.account_id, project_id: project.id).includes(:user).order(:id).to_a
      tasks = project.tasks.where(account_id: project.account_id, project_id: project.id)
      assigned = tasks.group(:assignee_id).count
      open_tasks = tasks.where.not(status: %w[completed canceled]).group(:assignee_id).count
      # Only aggregate workload is returned; names and IDs of other projects remain private.
      active_projects = Project.where(account_id: project.account_id, status: %w[planned active]).select(:id)
      allocations = ProjectMember.where(account_id: project.account_id, user_id: members.map(&:user_id), project_id: active_projects)
                                 .group(:user_id).sum(:allocation_percent)
      members.map do |member|
        allocation = allocations.fetch(member.user_id, 0)
        member.as_json(only: %i[id user_id role allocation_percent], include: { user: { only: %i[id name] } }).merge(
          'assigned_tasks_count' => assigned.fetch(member.user_id, 0), 'open_tasks_count' => open_tasks.fetch(member.user_id, 0),
          'total_allocation_percent' => allocation, 'available_percent' => [100 - allocation, 0].max,
          'overallocated' => allocation > 100, 'allocation_basis' => 'planned_and_active_projects'
        )
      end
    end

    def self.overview(project)
      tasks = project.tasks.where(account_id: project.account_id, project_id: project.id)
      time = project.time_entries.where(account_id: project.account_id, project_id: project.id)
      milestones = project.milestones.where(account_id: project.account_id, project_id: project.id)
      {
        status_counts: tasks.group(:status).count,
        overdue_tasks: tasks.where('due_on < ?', Date.current).where.not(status: %w[completed canceled]).count,
        team_size: project.project_members.where(account_id: project.account_id, project_id: project.id).count,
        estimated_minutes: tasks.sum(:estimated_minutes),
        estimated_configured: tasks.where('estimated_minutes > 0').exists?,
        worked_minutes: time.where.not(status: 'rejected').sum(:minutes),
        approved_minutes: time.where(status: 'approved').sum(:minutes),
        milestones_total: milestones.where.not(status: 'canceled').count,
        milestones: milestones.where.not(status: 'canceled').order(Arel.sql('due_on ASC NULLS LAST'), :id)
                              .limit(8).as_json(only: %i[id name due_on status phase_id]),
        upcoming_milestones: milestones.where(status: 'open').where.not(due_on: nil).order(:due_on, :id)
                                      .limit(5).as_json(only: %i[id name due_on status phase_id])
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
