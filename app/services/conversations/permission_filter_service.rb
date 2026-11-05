class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    restrict_inbox_visibility(user_role == 'administrator' ? conversations : accessible_conversations)
  end

  private

  def restrict_inbox_visibility(scope)
    Conversations::InboxVisibility.new(account: account, user: user).restrict(scope)
  end

  def accessible_conversations
    conversations.where(inbox: user.inboxes.where(account_id: account.id))
  end

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
