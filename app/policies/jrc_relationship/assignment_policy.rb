class JrcRelationship::AssignmentPolicy < JrcRelationship::ModulePolicy
  def show?
    access? && scope.exists?(id: record.id)
  end

  def update?
    manage? && show? && JrcRelationship::LocalAccess.assignment_allowed?(account_user, record, 'work')
  end

  def assign?
    team? && show? && JrcRelationship::LocalAccess.assignment_allowed?(account_user, record, 'execute_transfer')
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      boundary = JrcRelationship::ModulePolicy.new(user_context, account)
      relation = scope.where(account_id: account.id)
      return relation.none unless boundary.access?

      relation = JrcCrm::OrganizationalVisibility.new(account: account, user: user, relation: relation, include_company: false).call
      return JrcRelationship::LocalAccess.scope_assignments(user_context, relation) if boundary.admin?

      scoped = if boundary.team?
        ids = account.teams.joins(:team_members).where(team_members: { user_id: user.id }).select(:id)
        relation.where(owner_id: user.id).or(relation.where(team_id: ids)).or(relation.where(owner_id: nil, team_id: nil))
      else
        relation.where(owner_id: user.id)
      end
      JrcRelationship::LocalAccess.scope_assignments(user_context, scoped)
    end
  end
end
