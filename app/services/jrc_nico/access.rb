class JrcNico::Access
  attr_reader :account, :user, :conversation, :membership

  def initialize(account:, user:, conversation:)
    @account = account
    @user = user
    @conversation = conversation
    @membership = account.account_users.find_by(user_id: user&.id)
  end

  def authorize!
    account.reload
    @membership = account.account_users.find_by(user_id: user&.id)
    allowed = user.is_a?(User) && membership && account.active? && account.custom_attributes['nico_enabled'] == true
    allowed &&= conversation.account_id == account.id
    allowed &&= ConversationPolicy.new({ account: account, user: user, account_user: membership }, conversation).show?
    raise Pundit::NotAuthorizedError unless allowed

    self
  end

  def leads
    return JrcCrm::Lead.none unless crm?

    scope = JrcCrm::Lead.where(account_id: account.id, contact_id: conversation.contact_id)
    membership.administrator? ? scope : scope.where(owner_id: user.id)
  end

  def deals
    return JrcCrm::Deal.none unless crm?

    scope = JrcCrm::Deal.where(account_id: account.id, contact_id: conversation.contact_id)
    membership.administrator? ? scope : scope.where(owner_id: user.id)
  end

  def crm?
    JrcOperations::Access.crm?(membership)
  end
end
