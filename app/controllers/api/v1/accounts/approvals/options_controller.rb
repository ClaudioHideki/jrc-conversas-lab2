class Api::V1::Accounts::Approvals::OptionsController < Api::V1::Accounts::Approvals::BaseController
  def index
    company_id = params[:issuer_company_id].presence&.to_i
    unit_id = params[:business_unit_id].presence&.to_i
    authorization.authorize!('policy_manage', company_id: company_id, unit_id: unit_id)
    members = covered_members(company_id, unit_id)
    roles = Current.account.custom_roles.where(id: members.filter_map(&:custom_role_id))
    render json: {
      account_users: members.map { |member| { id: member.id, name: member.user.name } },
      teams: team_options(members), custom_roles: named_options(roles)
    }
  end

  private

  def covered_members(company_id, unit_id)
    # Native identities, projected for this authorized editor; no alternate user/team store.
    Current.account.account_users.includes(:user).select do |member|
      member.user.active_for_authentication? &&
        JrcApprovals::Authorization.new(
          account: Current.account, user: member.user
        ).covered?(company_id, unit_id)
    end
  end

  def team_options(members)
    teams = Current.account.teams.joins(:team_members).where(team_members: { user_id: members.map(&:user_id) }).distinct
    named_options(teams)
  end

  def named_options(records)
    records.map { |record| { id: record.id, name: record.name } }
  end
end
