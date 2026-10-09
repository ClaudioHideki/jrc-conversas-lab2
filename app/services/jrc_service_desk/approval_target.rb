# frozen_string_literal: true

class JrcServiceDesk::ApprovalTarget
  FIELDS = %w[approver_account_user_id approver_team_id approver_role approver_custom_role_id].freeze

  def initialize(context:, unit:)
    @context = context
    @unit = unit
  end

  def attributes(values)
    supplied = values.slice(*FIELDS).compact
    raise ArgumentError, 'Exactly one explicit approval target required' unless supplied.size == 1

    key, value = supplied.first
    target = case key
             when 'approver_account_user_id' then membership_target(value)
             when 'approver_team_id' then team_target(value)
             when 'approver_role' then role_target(value)
             when 'approver_custom_role_id' then custom_role_target(value)
             end
    raise Pundit::NotAuthorizedError, 'No eligible approver in this unit' unless eligible_members(target).exists?

    { approver_membership: nil, approver_team: nil, approver_role: nil, approver_custom_role_id: nil }.merge(target)
  end

  private

  def memberships
    JrcServiceDesk::UnitMembership.where(account_id: @context.account.id, unit_id: @unit.id, active: true).joins(:account_user)
  end

  def membership_target(value)
    member = memberships.find_by!(account_user_id: JrcServiceDesk::Input.id(value))
    { approver_membership: member }
  end

  def team_target(value)
    team = Team.where(account_id: @context.account.id).find(JrcServiceDesk::Input.id(value))
    Pundit.authorize(@context.to_h, team, :show?)
    { approver_team: team }
  end

  def role_target(value)
    raise ArgumentError, 'Supported native approval role required' unless %w[agent administrator].include?(value)

    { approver_role: value }
  end

  def custom_role_target(value)
    raise ArgumentError, 'Custom role is unavailable' unless defined?(CustomRole)

    role = CustomRole.where(account_id: @context.account.id).find(JrcServiceDesk::Input.id(value))
    { approver_custom_role_id: role.id }
  end

  def eligible_members(target)
    ids = memberships.filter_map do |membership|
      member = membership.account_user
      next unless capable?(member) && matches_target?(membership, member, target)

      membership.id
    end
    memberships.where(id: ids)
  end

  def capable?(member)
    target_context = JrcServiceDesk::OperationalContext.new(account: @context.account, user: member.user, account_user: member)
    target_context.capability?(:approvals_decide) && target_context.capability?(:tickets_view)
  end

  def matches_target?(membership, member, target)
    matches_membership?(membership, target) && matches_team?(member, target) && matches_role?(member, target) && matches_custom_role?(member, target)
  end

  def matches_membership?(membership, target)
    !target[:approver_membership] || target[:approver_membership].id == membership.id
  end

  def matches_team?(member, target)
    !target[:approver_team] || TeamMember.exists?(team_id: target[:approver_team].id, user_id: member.user_id)
  end

  def matches_role?(member, target)
    !target[:approver_role] || (member.role == target[:approver_role] && member.custom_role_id.nil?)
  end

  def matches_custom_role?(member, target)
    !target[:approver_custom_role_id] || member.custom_role_id == target[:approver_custom_role_id]
  end
end
