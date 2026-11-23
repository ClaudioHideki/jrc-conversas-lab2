# frozen_string_literal: true

class JrcContactCenter::EndingActions::ConfigurationContext
  def initialize(account:, member:)
    @account = account
    @member_id = member.id
    @user_id = member.user_id
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
    coverage = JrcContactCenter::CorporateCoverage.new(account: @account, user: member.user)
    raise Pundit::NotAuthorizedError unless allowed && (!coverage.configured? || coverage.group?)
  end
end
