class JrcProjects::Tasks::Create
  FIELDS = %w[title description priority assignee_id parent_id estimated_minutes starts_on due_on labels].freeze

  def self.call(account_user:, project:, attributes:, correlation_id: nil)
    new(account_user: account_user, project: project, attributes: attributes, correlation_id: correlation_id).call
  end

  def initialize(account_user:, project:, attributes:, correlation_id:)
    @member = JrcOperations::Access.refresh(account_user)
    @project_id = project.id
    @input = attributes.to_h.stringify_keys
    @correlation_id = correlation_id
  end

  def call
    raise Pundit::NotAuthorizedError unless @member

    project = JrcOperations::Access.projects(@member).find(@project_id)
    project.with_lock do
      authorize!(project)
      column = work_column(project)
      task = project.tasks.where(account_id: @member.account_id, project_id: project.id).create!(
        task_attributes(project).merge(account: @member.account, created_by: @member.user, board_column: column,
                                       status: column.status_key, position: (column.tasks.maximum(:position) || 0) + 1024)
      )
      JrcProjects::AuditEvent.record!(account: @member.account, actor: @member.user, action: 'projects.task.created', auditable: task,
                                      after_data: task.attributes, correlation_id: @correlation_id)
      task
    end
  end

  private

  def authorize!(project)
    allowed = JrcProjects::Authorization.allowed?(account_user: @member, capability: 'projects.task.create', project: project)
    raise Pundit::NotAuthorizedError unless allowed
    raise ArgumentError, 'Reabra o projeto antes de alterar tarefas.' if %w[completed canceled].include?(project.status)
  end

  def work_column(project)
    columns = project.board_columns.where(account_id: @member.account_id)
    column = @input['board_column_id'].present? ? columns.find(@input['board_column_id']) : columns.order(:position).first!
    raise ArgumentError, 'Crie a tarefa em uma coluna de trabalho.' if column.status_key == 'completed'
    raise JrcProjects::Errors::WipLimit, 'Limite desta coluna atingido.' if column.wip_limit && column.tasks.count >= column.wip_limit

    column
  end

  def task_attributes(project)
    values = @input.slice(*FIELDS)
    values['assignee_id'] = assignee_id(project, values['assignee_id']) if values.key?('assignee_id')
    values['parent_id'] = parent_id(project, values['parent_id']) if values.key?('parent_id')
    values
  end

  def assignee_id(project, value)
    user = @member.account.users.find(value) if value.present?
    project.project_members.where(account_id: @member.account_id, project_id: project.id).find_by!(user_id: user.id) if user
    user&.id
  end

  def parent_id(project, value)
    parent = project.tasks.where(account_id: @member.account_id, project_id: project.id).find(value) if value.present?
    parent&.id
  end
end
