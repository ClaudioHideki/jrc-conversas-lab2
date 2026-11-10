# The same native project/task authority used by the task editor. A reviewed
# handoff can change an assignee, never project membership or historical authors.
class JrcProjects::Tasks::Assign
  def self.call(account_user:, task_id:, assignee_id:, expected_lock_version:, correlation_id:)
    member = JrcOperations::Access.refresh(account_user)
    project = JrcOperations::Access.projects(member).joins(:tasks)
                                   .where(jrc_projects_tasks: { account_id: member.account_id, id: task_id }).first!
    project.with_lock do
      raise ArgumentError, 'Reopen the project before transferring pending tasks' if %w[completed canceled].include?(project.status)

      task = task!(member, project, task_id, expected_lock_version)
      user = assignee!(member, project, assignee_id)
      persist!(member, project, task, user, correlation_id)
    end
  end

  def self.task!(member, project, task_id, version)
    task = project.tasks.where(account_id: member.account_id).lock.find(task_id)
    unless JrcProjects::Authorization.allowed?(account_user: member, capability: 'projects.task.view', project: project) &&
           JrcProjects::Authorization.allowed?(account_user: member, capability: 'projects.task.update', project: project, record: task)
      raise Pundit::NotAuthorizedError
    end
    raise ActiveRecord::StaleObjectError.new(task, 'update') unless task.lock_version == Integer(version)
    raise ArgumentError, 'Only pending tasks can be transferred' if %w[completed canceled].include?(task.status)

    task
  end

  def self.assignee!(member, project, id)
    user = member.account.users.lock('FOR SHARE').find(id)
    raise Pundit::NotAuthorizedError unless user.active_for_authentication?

    project.project_members.where(account_id: member.account_id).lock('FOR SHARE').find_by!(user_id: user.id)
    user
  end

  def self.persist!(member, project, task, user, correlation_id)
    before = task.attributes
    task.update!(assignee: user)
    target = member.account.account_users.lock('FOR SHARE').find_by!(user: user)
    unless JrcOperations::Access.projects(target).exists?(id: project.id) &&
           JrcProjects::Authorization.allowed?(account_user: target, capability: 'projects.task.update', project: project, record: task)
      raise Pundit::NotAuthorizedError
    end

    if task.saved_changes.any?
      JrcProjects::AuditEvent.record!(account: member.account, actor: member.user, action: 'projects.task.updated', auditable: task,
                                      before_data: before, after_data: task.attributes, correlation_id: correlation_id)
    end
    task
  end

  private_class_method :task!, :assignee!, :persist!
end
