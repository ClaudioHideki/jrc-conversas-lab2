# frozen_string_literal: true

class JrcContactCenter::EndingActions::ConfigurationContext
  def initialize(account:, member:, for_rule: false)
    @account = account
    @member_id = member.id
    @user_id = member.user_id
    @for_rule = for_rule
  end

  def call
    JrcContactCenter::AuthorityTransaction.call(account: @account, member: nil) do
      member = @account.account_users.find_by!(id: @member_id, user_id: @user_id)
      authorize!(member)
      JrcServiceDesk::NativeExecutionContext.with(account: @account, account_user: member, user: member.user) do
        yield member
      end
    end
  end

  private

  def authorize!(member)
    context = { account: @account, account_user: member, user: member.user }
    allowed = member.user.reload.active_for_authentication? && JrcContactCenter::ModulePolicy.new(context, :contact_center).configure?
    raise Pundit::NotAuthorizedError unless allowed && coverage_allowed?(member)
  end

  # Per-rule editors still require an actual native organizational scope. The
  # global ACW writer keeps its previous whole-account coverage requirement.
  def coverage_allowed?(member)
    coverage = JrcContactCenter::CorporateCoverage.new(account: @account, user: member.user)
    return true unless coverage.configured? && !coverage.group?

    @for_rule && JrcContactCenter::OrganizationalScope.new(account: @account, account_user: member).units.exists?
  end
end
