# An additive list scope. The underlying conversation permissions remain authoritative.
class Conversations::SharedInboxScope
  def initialize(conversations:, account:, user:, include_participating: false, member_inboxes_only: false)
    @conversations = conversations
    @account = account
    @user = user
    @include_participating = include_participating
    @member_inboxes_only = member_inboxes_only
  end

  def metadata
    @metadata ||= begin
      ids = member_inbox_ids - Conversations::InboxVisibility.new(account: @account, user: @user).exclusive_inbox_ids
      enabled = allowed? && ids.any?
      shared = enabled ? Conversations::SharedInboxRouting.new(account: @account, user: @user, inbox_ids: ids).perform : []
      # The remote snapshot must not retain access revoked while HTTP was in flight.
      ApplicationRecord.uncached do
        current_metadata(enabled && allowed?, shared)
      end
    end
  end

  def perform
    scope = metadata
    permitted, shared_ids = ApplicationRecord.uncached do
      [Conversations::PermissionFilterService.new(@conversations, @user, @account).perform, allowed? ? scope[:inbox_ids] : []]
    end
    mine = permitted.assigned_to(@user)
    if @include_participating
      participants = ConversationParticipant.where(account_id: @account.id, user_id: @user.id).select(:conversation_id)
      mine = mine.or(permitted.where(id: participants))
    end
    mine.or(permitted.where(inbox_id: shared_ids, assignee_agent_bot_id: nil))
  end

  private

  def current_metadata(enabled, shared)
    result = { enabled: enabled, inbox_ids: enabled ? (shared & member_inbox_ids).sort : [] }
    result[:member_inbox_ids] = current_member_inbox_ids if @member_inboxes_only
    supervised = Conversations::InboxVisibility.new(account: @account, user: @user).supervised_inbox_ids
    result[:supervised_inbox_ids] = supervised if supervised.any?
    result
  end

  def current_member_inbox_ids
    @account.account_users.exists?(user_id: @user.id) ? member_inbox_ids.sort : []
  end

  def allowed?
    member = @account.account_users.find_by(user_id: @user.id)
    return false unless member && %w[agent administrator].include?(member.role)
    return true if member.custom_role_id.nil?

    member.permissions.include?('conversation_manage')
  end

  def member_inbox_ids
    InboxMember.where(user_id: @user.id, inbox_id: @account.inboxes.select(:id)).pluck(:inbox_id)
  end
end
