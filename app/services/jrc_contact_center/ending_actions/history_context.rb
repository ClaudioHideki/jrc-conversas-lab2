# frozen_string_literal: true

# Read-only authority for one native attendance, rebuilt under the same account
# lock used by eligibility and corporate/profile changes. No configuration grant
# substitutes for the separate native audit authority when viewing another agent.
class JrcContactCenter::EndingActions::HistoryContext
  def initialize(account:, member:, qualification_id:)
    @account = account
    @member = member
    @qualification_id = qualification_id
  end

  def call
    JrcContactCenter::AuthorityTransaction.call(account: @account, member: @member) do
      member = JrcOperations::Access.refresh(@member)
      raise Pundit::NotAuthorizedError unless member && member.user.reload.active_for_authentication?

      context = { account: @account, account_user: member, user: member.user }
      access = JrcContactCenter::AccessScope.new(user_context: context)
      raise Pundit::NotAuthorizedError unless access.policy.access?

      record = JrcContactCenter::Qualification.where(account: @account).find(@qualification_id)
      authorize_agent!(access, record, member)
      authorize_origin!(access, record, context)
      yield member, record
    end
  end

  private

  def authorize_agent!(access, record, member)
    allowed = access.full_access? && access.policy.audit?
    allowed ||= record.account_user_id == member.id && access.policy.operate?
    raise Pundit::NotAuthorizedError unless allowed
  end

  def authorize_origin!(access, record, context)
    return access.call_sessions.find(record.call_session_id) if record.call_session_id

    conversation = @account.conversations.find(record.conversation_id)
    raise Pundit::NotAuthorizedError unless ConversationPolicy.new(context, conversation).show?
    raise Pundit::NotAuthorizedError unless access.full_access? || conversation.assignee_id == context.fetch(:user).id
  end
end
