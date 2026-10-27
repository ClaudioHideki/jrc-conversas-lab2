# A response-only snapshot. Construct in a GET action and pass explicitly to its
# serializers; never use this projection to authorize a write.
class JrcProjects::ReadProjection
  EMPTY_CAPABILITIES = [].freeze
  CARD_CAPABILITIES = (JrcProjects::Authorization::OWNER + ['projects.project.create']).freeze

  def initialize(account_user:, projects:)
    member = JrcOperations::Access.refresh(account_user)
    initialize_authority(member)
    scoped_projects = projects.select { |project| project.account_id == @account_id }
    initialize_capabilities(scoped_projects)
    @directory_access = member&.account&.feature_enabled?('jrc_customer_master') &&
                        JrcCustomers::DirectoryPolicy.new(JrcOperations::Access.user_context(member), :directory).access?
    @companies = companies(scoped_projects).freeze
    freeze
  end

  def capabilities(project)
    return EMPTY_CAPABILITIES unless project.account_id == @account_id

    @capabilities.fetch(project.id, EMPTY_CAPABILITIES)
  end

  def directory_access?(project)
    @directory_access && project.account_id == @account_id
  end

  def company(project)
    @companies[project.company_id] if directory_access?(project)
  end

  def task_permissions(task)
    grants = task.account_id == @account_id ? @capabilities.fetch(task.project_id, EMPTY_CAPABILITIES) : EMPTY_CAPABILITIES
    {
      'can_update' => task_update?(task, grants),
      'can_move' => grants.include?('projects.task.move'),
      'can_delete' => grants.include?('projects.task.delete')
    }
  end

  private

  def initialize_capabilities(projects)
    memberships = membership_roles(projects)
    @contributor_project_ids = projects.filter_map do |project|
      project.id if project.owner_id != @user_id && memberships[project.id] == 'contributor'
    end.freeze
    @capabilities = projects.to_h do |project|
      [project.id, project_capabilities(project, memberships).map { |capability| capability.dup.freeze }.freeze]
    end.freeze
  end

  def task_update?(task, grants)
    return false unless grants.include?('projects.task.update')
    return true unless @contributor_project_ids.include?(task.project_id)

    task.assignee_id == @user_id || task.created_by_id == @user_id
  end

  def initialize_authority(member)
    return unless member

    account = member.account.reload
    @account_id = account.id
    @user_id = member.user_id
    @admin = member.administrator? && member.custom_role_id.nil?
    @enabled = projects_enabled?(account, member)
    @permissions = role_permissions(member)&.map { |permission| permission.dup.freeze }&.freeze
  end

  def projects_enabled?(account, member)
    account.active? && account.feature_enabled?('jrc_projects') && (@admin || member.jrc_projects_enabled?)
  end

  def role_permissions(member)
    return if member.custom_role_id.blank?

    role = member.custom_role
    return [] unless role && role.account_id == @account_id && member.permissions.include?('custom_role')

    role.permissions
  end

  def membership_roles(projects)
    return {} unless @enabled && !@admin

    JrcProjects::ProjectMember.where(account_id: @account_id, user_id: @user_id, project_id: projects.map(&:id)).pluck(:project_id, :role).to_h
  end

  def project_capabilities(project, memberships)
    return EMPTY_CAPABILITIES unless @enabled

    grants = project_grants(project, memberships)
    CARD_CAPABILITIES.select do |capability|
      grants.include?(capability) && (@permissions.nil? || @permissions.include?(JrcProjects::Authorization.permission(capability)))
    end
  end

  def project_grants(project, memberships)
    return CARD_CAPABILITIES if @admin
    return JrcProjects::Authorization::OWNER if project.owner_id == @user_id

    if memberships.key?(project.id)
      # Membership named owner does not confer ownership transfer.
      return JrcProjects::Authorization::ROLE_GRANTS.fetch(memberships[project.id], []) - ['projects.project.transfer']
    end

    project.visibility == 'account' ? JrcProjects::Authorization::VIEW : EMPTY_CAPABILITIES
  end

  def companies(projects)
    return {} unless @directory_access

    JrcCustomers::Company.where(account_id: @account_id, id: projects.filter_map(&:company_id)).to_h do |company|
      [company.id, company.as_json(only: %i[id name]).transform_values(&:freeze).freeze]
    end
  end
end
