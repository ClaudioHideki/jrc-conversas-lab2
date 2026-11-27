# frozen_string_literal: true

# Invoked only after SyntheticRecordingsSeed's existing owned environment/account
# guard. Explicit synthetic Projects grants never activate a real user or provider.
class JrcContactCenter::SyntheticRecordingTaskSeed
  RIGHTS = %w[jrc_projects_project_view jrc_projects_task_view jrc_projects_task_create
              jrc_projects_task_update jrc_projects_task_assign jrc_projects_member_view].freeze

  def self.call(account:, operator:)
    owner = account.account_users.where(role: :administrator).where.not(id: operator.id).sole
    account.enable_features!('jrc_projects')
    authorize_synthetic_destinations(owner, operator)
    JrcServiceDesk::NativeExecutionContext.with(account: account, account_user: owner, user: owner.user) do
      allowed = create_project(account, owner, 'SYNTHETIC recording actions permitted project')
      hidden = create_project(account, owner, 'SYNTHETIC recording actions PRIVATE excluded project')
      JrcProjects::ProjectMember.create!(account: account, project: allowed, user: operator.user, role: 'member')
      present(allowed, hidden, operator)
    end
  end

  def self.present(allowed, hidden, operator)
    { project_id: allowed.id.to_s, project_name: allowed.name, hidden_project_id: hidden.id.to_s, hidden_project_name: hidden.name,
      assignee_id: operator.user_id.to_s, assignee_name: operator.user.name,
      column_id: allowed.board_columns.find_by!(status_key: 'backlog').id.to_s }
  end

  def self.authorize_synthetic_destinations(owner, operator)
    owner.update!(jrc_projects_enabled: true,
                  jrc_projects_permissions: { 'projects.project.create' => true, 'projects.task.move' => true })
    owner_rights = RIGHTS + %w[jrc_projects_project_create jrc_projects_task_move]
    owner.custom_role.update!(permissions: (owner.custom_role.permissions + owner_rights).uniq)
    operator.update!(jrc_projects_enabled: true, jrc_projects_permissions: { 'projects.task.create' => true, 'projects.task.assign' => true })
    operator.custom_role.update!(permissions: (operator.custom_role.permissions + RIGHTS).uniq)
  end

  def self.create_project(account, owner, name)
    JrcProjects::Projects::Create.call(account: account, actor: owner.user,
                                       attributes: { name: name, visibility: 'private' }, idempotency_key: SecureRandom.uuid)
  end
  private_class_method :create_project, :authorize_synthetic_destinations, :present
end
