class JrcNico::BrokerSendCommitGate
  LOCK = 'FOR SHARE NOWAIT'.freeze

  def self.call(operation:, conversation:, integration:)
    ActiveRecord::Base.uncached do
      account, user = lock_authority(operation)
      lock_grants(user, account, conversation)
      lock_destination(operation, conversation, integration)
      raise Pundit::NotAuthorizedError unless user.active_for_authentication?

      # New objects and uncached queries prevent a previous policy read from
      # retaining a grant which was revoked before these row locks were acquired.
      access = JrcNico::OperationalAccess.new(account: account, user: user)
      JrcNico::BrokerSendCoordinator.validate_local!(operation, access)
      yield
    end
  end

  def self.lock_authority(operation)
    account = Account.lock(LOCK).find(operation.account_id)
    user = User.lock(LOCK).find(operation.user_id)
    member = AccountUser.lock(LOCK).find_by!(account_id: account.id, user_id: user.id)
    CustomRole.lock(LOCK).find(member.custom_role_id) if member.custom_role_id
    Inbox.lock(LOCK).find(operation.inbox_id)
    [account, user]
  end

  def self.lock_destination(operation, conversation, expected_integration)
    current = JrcBrokerIntegration.lock(LOCK).find_by!(account_id: operation.account_id)
    validate_integration!(operation, current, expected_integration)
    binding = JrcNico::BrokerSendBinding.resolve(account_id: operation.account_id, inbox_id: operation.inbox_id, lock: LOCK)
    raise ArgumentError, JrcNico::BrokerSendBinding::UNAVAILABLE unless binding

    Contact.lock(LOCK).find(conversation.contact_id)
    ContactInbox.lock(LOCK).find(conversation.contact_inbox_id)
  end

  def self.validate_integration!(operation, current, expected)
    same_client = current.attributes.except('created_at', 'updated_at') == expected.attributes.except('created_at', 'updated_at')
    same_scope = current.organization_id == operation.snapshot['organizationId'] &&
                 current.destination_revision == operation.snapshot['destinationRevision'] && current.account_id == operation.account_id
    raise ArgumentError, 'A configuração da integração mudou antes do registro da mensagem.' unless same_client && same_scope
  end

  def self.lock_grants(user, account, conversation)
    InboxMember.where(user_id: user.id, inbox_id: conversation.inbox_id).order(:id).lock(LOCK).load
    if conversation.team_id
      Team.lock(LOCK).find(conversation.team_id)
      TeamMember.where(user_id: user.id, team_id: conversation.team_id).order(:id).lock(LOCK).load
    end
    ConversationParticipant.where(account_id: account.id, user_id: user.id, conversation_id: conversation.id).order(:id).lock(LOCK).load
  end
  private_class_method :lock_authority, :lock_destination, :validate_integration!, :lock_grants
end
