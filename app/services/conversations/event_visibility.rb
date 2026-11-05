class Conversations::EventVisibility
  def self.tokens(conversation)
    account = conversation.account
    tokens = (conversation.inbox.members.pluck(:pubsub_token) + account.administrators.pluck(:pubsub_token)).uniq
    filter_tokens(account: account, conversation: conversation, tokens: tokens)
  end

  def self.filter_tokens(account:, conversation:, tokens:)
    new(account: account, conversation: conversation, tokens: tokens).filter
  end

  def self.reference(event_name, data)
    return { display_id: data[:conversation_id] } if event_name.start_with?('message.') || event_name == 'first.reply.created'
    return { display_id: data[:conversation][:id] } if data[:conversation].is_a?(Hash)
    return notification_reference(data) if %w[notification.created notification.updated].include?(event_name)
    return unless data[:id] && (event_name.start_with?('conversation.') || %w[assignee.changed team.changed].include?(event_name))

    { display_id: data[:id] }
  end

  def self.notification_reference(data)
    item = data[:notification]
    { id: item[:primary_actor_id] } if item&.dig(:primary_actor_type) == 'Conversation'
  end
  private_class_method :notification_reference

  def initialize(account:, conversation:, tokens:)
    @account = account
    @conversation = conversation
    @tokens = tokens
    @policy = JrcHumanAssignment::Policy.connection_for(account, conversation.inbox_id)
  end

  def filter
    return @tokens unless @policy&.fetch('visibility', nil) == 'assigned_only'

    @users = User.where(pubsub_token: @tokens).index_by(&:pubsub_token)
    @members = @account.account_users.where(user_id: @users.values.map(&:id)).index_by(&:user_id)
    @candidates = [@conversation.assignee_id] + Array(@policy['supervisor_ids'])
    @tokens.select { |token| allowed_token?(token) }
  end

  private

  def allowed_token?(token)
    user = @users[token]
    return customer_tokens.include?(token) unless user

    member = @members[user.id]
    return false unless member && (@candidates.include?(user.id) || administrator?(member))

    ConversationPolicy.new({ account: @account, user: user, account_user: member }, @conversation).show?
  end

  def administrator?(member)
    member.administrator? && member.custom_role_id.nil?
  end

  def customer_tokens
    @customer_tokens ||= @conversation.contact.contact_inboxes.where(inbox_id: @account.inboxes.select(:id)).pluck(:pubsub_token)
  end
end
