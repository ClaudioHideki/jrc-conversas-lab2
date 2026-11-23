# frozen_string_literal: true

# Worker entry boundary, never an HTTP grant or automatic activation. There is no
# actor input: every attempt resolves the original attested account/user pair.
class JrcContactCenter::EndingActions::OriginalActorContext
  def initialize(account:, origin_id:)
    @account = account
    @origin_id = origin_id
  end

  def call
    JrcContactCenter::EndingActions::ExecutionTransaction.call(account: @account) do
      origin = JrcContactCenter::EndingActionOrigin.where(account: @account).find(@origin_id)
      member = @account.account_users.find_by!(id: origin.actor_account_user_id, user_id: origin.actor_user_id)
      JrcContactCenter::EndingActions::SourceAuthority.new(account: @account, member: member).call(origin)
      JrcServiceDesk::NativeExecutionContext.with(account: @account, account_user: member, user: member.user) do
        yield member, origin
      end
    end
  end
end
