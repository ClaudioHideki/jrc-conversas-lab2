# frozen_string_literal: true

# Unapplied WIP configuration validation. The caller must retain native CC
# configure/global-coverage authority; this class adds only destination restrictions.
class JrcContactCenter::EndingActions::ProjectTaskParameters
  def initialize(member:)
    @member = JrcOperations::Access.refresh(member)
  end

  def call(input)
    row, project = authorized_reference(input)
    validate_current_destination!(project, row.fetch('attributes'))
    row
  end

  # Reading/replacing an old template still requires its current native project
  # and functional authority, but a closed project or removed column must not make
  # an otherwise authorized historical template impossible to correct.
  def authorize_reference!(input)
    authorized_reference(input).first
  end

  private

  def authorized_reference(input)
    raise Pundit::NotAuthorizedError unless @member && @member.user.reload.active_for_authentication?

    row = JrcContactCenter::EndingActions::TaskDefinition.new.call(input)
    project = JrcOperations::Access.projects(@member).find(row.fetch('project_id'))
    values = row.fetch('attributes')
    allowed = JrcProjects::Authorization.allowed?(account_user: @member, capability: 'projects.task.create', project: project)
    raise Pundit::NotAuthorizedError unless allowed

    if values['assignee_id'] && !JrcProjects::Authorization.allowed?(account_user: @member, capability: 'projects.task.assign', project: project)
      raise Pundit::NotAuthorizedError
    end

    [row, project]
  end

  def validate_current_destination!(project, values)
    authorize_assignment!(project, values['assignee_id']) if values['assignee_id']
    project.tasks.where(account_id: @member.account_id).find(values['parent_id']) if values['parent_id']

    column = project.board_columns.where(account_id: @member.account_id).find(values.fetch('board_column_id'))
    invalid! if column.status_key == 'completed' || %w[completed canceled].include?(project.status)
  end

  def authorize_assignment!(project, assignee_id)
    user = @member.account.users.find(assignee_id)
    project.project_members.where(account_id: @member.account_id).find_by!(user_id: user.id)
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_ending_task_parameters'
  end
end
