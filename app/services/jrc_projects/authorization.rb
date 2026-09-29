module JrcProjects
  class Authorization
    VIEW = %w[projects.project.view projects.task.view projects.report.view].freeze
    WORK = (VIEW + %w[projects.task.create projects.task.update projects.task.move projects.time_entry.create]).freeze
    MANAGE = (WORK + %w[projects.project.update projects.member.manage projects.board.manage projects.task.delete projects.milestone.manage projects.sprint.manage projects.risk.manage projects.issue.manage projects.decision.manage projects.report.export projects.time_entry.manage projects.attachment.manage]).freeze
    OWNER = (MANAGE + %w[projects.budget.view projects.budget.manage projects.project.delete projects.project.transfer]).freeze
    ROLE_GRANTS = { 'owner' => OWNER, 'manager' => MANAGE, 'member' => WORK, 'contributor' => VIEW + %w[projects.task.update projects.time_entry.create], 'viewer' => VIEW }.freeze
    def self.allowed?(account_user:, capability:, project: nil, record: nil)
      account_user = JrcOperations::Access.refresh(account_user)
      return false unless JrcOperations::Access.project_access?(account_user)
      if account_user.custom_role_id.present?
        role = account_user.custom_role
        return false unless role && role.account_id == account_user.account_id && account_user.permissions.include?('custom_role')
        return false unless role.permissions.include?(permission(capability))
      end
      return false if project && project.account_id != account_user.account_id
      return false if record && record.respond_to?(:account_id) && record.account_id != account_user.account_id
      if capability == 'projects.project.transfer'
        return project.present? && (JrcOperations::Access.admin?(account_user) || project.owner_id == account_user.user_id)
      end
      return true if JrcOperations::Access.admin?(account_user)
      if project.nil?
        return true if capability == 'projects.project.create'
        return %w[projects.project.view projects.report.view].include?(capability)
      end
      return true if project.owner_id == account_user.user_id && OWNER.include?(capability)
      member = project.project_members.where(account_id: account_user.account_id, project_id: project.id).find_by(user_id: account_user.user_id)
      return VIEW.include?(capability) if !member && project.visibility == 'account'
      return false unless member && ROLE_GRANTS.fetch(member.role, []).include?(capability)
      if member.role == 'contributor' && record.is_a?(Task) && capability == 'projects.task.update'
        return record.assignee_id == account_user.user_id || record.created_by_id == account_user.user_id
      end
      true
    end
    def self.permission(capability)
      'jrc_' + capability.tr('.', '_')
    end
    PERMISSIONS = (OWNER + %w[projects.project.create projects.template.manage]).map { |cap| permission(cap) }.freeze
    def self.capabilities(account_user, project)
      (OWNER + ['projects.project.create']).select { |cap| allowed?(account_user: account_user, capability: cap, project: project) }
    end
  end
end
