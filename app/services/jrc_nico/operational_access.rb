class JrcNico::OperationalAccess
  attr_reader :account, :user, :membership

  def initialize(account:, user:)
    @account, @user = account, user
    @membership = account.account_users.find_by(user_id: user&.id)
  end

  def authorize!
    account.reload
    @membership = account.account_users.find_by(user_id: user&.id)
    raise Pundit::NotAuthorizedError unless user.is_a?(User) && membership && account.active? && account.custom_attributes['nico_enabled'] == true

    self
  end

  def policy(record)
    Pundit.policy!({ account: account, user: user, account_user: membership }, record)
  end

  def inbox_visible?(inbox)
    # InboxPolicy and User#assigned_inboxes require request-local context, also in background jobs.
    previous_context = [Current.account, Current.user, Current.account_user]
    Current.account, Current.user, Current.account_user = account, user, membership
    policy(inbox).show?
  ensure
    Current.account, Current.user, Current.account_user = previous_context
  end

  def crm?
    JrcOperations::Access.crm?(membership)
  end

  def campaigns?
    account.feature_enabled?('jrc_campaigns') && membership.administrator?
  end

  def crm_scope(relation, owner: :owner_id)
    raise Pundit::NotAuthorizedError unless crm?

    scoped = relation.where(account_id: account.id)
    membership.administrator? ? scoped : scoped.where(owner => user.id)
  end

  def conversation(id)
    record = account.conversations.find_by!(display_id: id)
    raise Pundit::NotAuthorizedError unless policy(record).show?

    record
  end

  def contact(id, action = :show?)
    record = account.contacts.find(id)
    raise Pundit::NotAuthorizedError unless policy(record).public_send(action)

    record
  end

  def conversations
    # Match the authoritative per-resource policy, including Enterprise custom roles.
    account.conversations.order(updated_at: :desc).limit(200).select { |record| policy(record).show? }
  end
end
