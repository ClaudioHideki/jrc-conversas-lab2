# This restriction composes with RBAC; it never grants access to an inbox.
class Conversations::InboxVisibility
  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def exclusive_inbox_ids
    @exclusive_inbox_ids ||= begin
      ids = JrcHumanAssignment::Policy.connections(@account).filter_map { |id, policy| id.to_i if policy['visibility'] == 'assigned_only' }
      ids.empty? ? [] : @account.inboxes.where(id: ids).pluck(:id)
    end
  end

  def restrict(scope)
    return scope if exclusive_inbox_ids.empty? || administrator?
    return scope.none unless member

    restricted = exclusive_inbox_ids - supervised_inbox_ids
    owned = scope.where(conversations: { inbox_id: member_inbox_ids, assignee_id: @user.id })
    scope.where.not(conversations: { inbox_id: exclusive_inbox_ids }).or(
      scope.where(conversations: { inbox_id: supervised_inbox_ids })
    ).or(owned.where(conversations: { inbox_id: restricted }))
  end

  def visible?(conversation)
    return false unless conversation.account_id == @account.id
    return true unless exclusive_inbox_ids.include?(conversation.inbox_id)
    return true if administrator?
    return false unless member_of?(conversation.inbox_id)

    conversation.assignee_id == @user.id || supervised_inbox_ids.include?(conversation.inbox_id)
  end

  def member_of?(inbox_id)
    member.present? && member_inbox_ids.include?(inbox_id)
  end

  def supervised_inbox_ids
    @supervised_inbox_ids ||= exclusive_inbox_ids.select do |id|
      policy = JrcHumanAssignment::Policy.connection_for(@account, id)
      member_inbox_ids.include?(id) && Array(policy['supervisor_ids']).include?(@user.id)
    end
  end

  private

  def member
    @member ||= @account.account_users.find_by(user_id: @user.id)
  end

  def administrator?
    member&.administrator? && member.custom_role_id.nil?
  end

  def member_inbox_ids
    @member_inbox_ids ||= InboxMember.where(user_id: @user.id, inbox_id: @account.inboxes.select(:id)).pluck(:inbox_id)
  end
end
