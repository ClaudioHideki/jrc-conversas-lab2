class JrcNico::Access
  attr_reader :account, :user, :conversation, :membership

  def initialize(account:, user:, conversation:)
    @account = account
    @user = user
    @conversation = conversation
    @membership = account.account_users.find_by(user_id: user&.id)
  end

  def authorize!
    @membership = JrcNico::OperationalAccess.new(account: account, user: user).authorize!.membership
    allowed = conversation.account_id == account.id
    allowed &&= JrcMigrations::Visibility.scope(account.contacts, account: account, domain: 'contacts').exists?(id: conversation.contact_id)
    allowed &&= ConversationPolicy.new({ account: account, user: user, account_user: membership }, conversation).show?
    raise Pundit::NotAuthorizedError unless allowed

    self
  end

  def leads
    return JrcCrm::Lead.none unless crm?

    scope = JrcNico::MigrationVisibility.scope(JrcCrm::Lead, account: account).where(contact_id: conversation.contact_id)
    membership.administrator? ? scope : scope.where(owner_id: user.id)
  end

  def deals
    return JrcCrm::Deal.none unless crm?

    scope = JrcNico::MigrationVisibility.scope(JrcCrm::Deal, account: account).where(contact_id: conversation.contact_id)
    membership.administrator? ? scope : scope.where(owner_id: user.id)
  end

  def crm?
    JrcOperations::Access.crm?(membership)
  end
end
