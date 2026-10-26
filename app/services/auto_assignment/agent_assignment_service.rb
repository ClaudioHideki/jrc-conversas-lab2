class AutoAssignment::AgentAssignmentService
  # Allowed agent ids: array
  # This is the list of agents from which an agent can be assigned to this conversation
  # examples: Agents with assignment capacity, Agents who are members of a team etc
  pattr_initialize [:conversation!, :allowed_agent_ids!, :replace_inaccessible_assignee]

  def find_assignee
    return if conversation.inbox.auto_assignment_v2_enabled?
    return if JrcHumanAssignment::Policy.enabled_for?(conversation.account, conversation.inbox_id)

    rules = AutoAssignment::Eligibility.new(inbox: conversation.inbox, conversation: conversation)
    return unless rules.configuration_reason.nil?
    return unless rules.conversation_reason(allow_inaccessible_assignee: replace_inaccessible_assignee).nil?

    round_robin_manage_service.available_agent(allowed_agent_ids: allowed_online_agent_ids)
  end

  def perform
    callback_conversation = conversation
    # Create callbacks load trigger-generated attributes without clearing the
    # original event changes. Lock a persisted copy and keep that history intact.
    @conversation = Conversation.where(account_id: conversation.account_id).find(conversation.id)
    conversation.account.with_lock do
      conversation.with_lock do
        new_assignee = find_assignee
        next unless new_assignee

        member = conversation.account.account_users.find_by(user_id: new_assignee.id)
        next unless member

        member.with_lock do
          rules = AutoAssignment::Eligibility.new(inbox: conversation.inbox.reload, conversation: conversation)
          next if conversation.inbox.auto_assignment_v2_enabled?
          next if JrcHumanAssignment::Policy.enabled_for?(conversation.inbox.account, conversation.inbox_id)
          next unless rules.configuration_reason.nil? &&
                      rules.conversation_reason(allow_inaccessible_assignee: replace_inaccessible_assignee).nil? && rules.agent_reason(member).nil?

          conversation.update!(assignee: new_assignee)
          callback_conversation.assignee = new_assignee
          callback_conversation.clear_attribute_changes(['assignee_id'])
        end
      end
    end
  end

  private

  def online_agent_ids
    online_agents = OnlineStatusTracker.effective_available_users(conversation.account_id)
    online_agents.select { |_key, value| value.eql?('online') }.keys if online_agents.present?
  end

  def allowed_online_agent_ids
    # We want to perform roundrobin only over online agents
    # Hence taking an intersection of online agents and allowed member ids

    # the online user ids are string, since its from redis, allowed member ids are integer, since its from active record
    eligible_ids = conversation.account.account_users.online.where(auto_assignment_enabled: true).pluck(:user_id).map(&:to_s)
    Array(online_agent_ids) & Array(allowed_agent_ids).map(&:to_s) & eligible_ids
  end

  def round_robin_manage_service
    @round_robin_manage_service ||= AutoAssignment::InboxRoundRobinService.new(inbox: conversation.inbox)
  end

  def round_robin_key
    format(::Redis::Alfred::ROUND_ROBIN_AGENTS, inbox_id: conversation.inbox_id)
  end
end
