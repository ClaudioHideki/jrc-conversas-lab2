class JrcRelationship::AssignmentPolicy < JrcRelationship::ModulePolicy
  def show?
    access? && scope.exists?(id: record.id)
  end

  def update?
    manage? && show?
  end

  def assign?
    team? && show?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      boundary = JrcRelationship::ModulePolicy.new(user_context, account)
      relation = scope.where(account_id: account.id)
      return relation.none unless boundary.access?
      return relation if boundary.admin?

      relation = if boundary.team?
                   ids = account.teams.joins(:team_members).where(team_members: { user_id: user.id }).select(:id)
                   relation.where(owner_id: user.id).or(relation.where(team_id: ids)).or(relation.where(owner_id: nil, team_id: nil))
                 else
                   relation.where(owner_id: user.id)
                 end
      # Assignment.company is the served customer; organizational Company is
      # internal. Only its native business_unit is an operational boundary here.
      JrcCrm::OrganizationalVisibility.new(account: account, user: user, relation: relation, include_company: false).call
    end
  end
end
