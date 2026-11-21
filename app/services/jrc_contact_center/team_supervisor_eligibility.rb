# frozen_string_literal: true

# Role, eligibility and coverage are inspected, never copied into a new grant or TeamMember.
class JrcContactCenter::TeamSupervisorEligibility
  def initialize(account:, team:)
    @account = account
    @team = team
  end

  def reason(member)
    return 'unavailable' unless member.account_id == @account.id && @team.account_id == @account.id
    return 'inactive' unless member.user.reload.active_for_authentication?

    context = { account: @account, account_user: member, user: member.user }
    return 'permission' unless JrcContactCenter::ModulePolicy.new(context, :contact_center).supervise?
    return 'coverage' unless JrcContactCenter::TeamSupervisionScope.new(account: @account, team: @team, member: member).covered?

    nil
  end

  def present(member)
    raise ActiveRecord::RecordNotFound unless member.account_id == @account.id && @team.account_id == @account.id

    unavailable = reason(member)
    { account_user_id: member.id.to_s, name: member.user.name, eligible: unavailable.nil?, reason: unavailable }
  end
end
