class AutoAssignment::Diagnostics
  pattr_initialize [:inbox!, :conversation]

  def perform
    rules = AutoAssignment::Eligibility.new(inbox: inbox, conversation: conversation)
    configuration_reason = rules.configuration_reason
    human_policy = JrcHumanAssignment::Policy.for(inbox.account) if JrcHumanAssignment::Policy.enabled_for?(inbox.account, inbox.id)
    presence = OnlineStatusTracker.effective_presence(inbox.account_id)
    counts = Hash.new(0)
    account_users = inbox.account.account_users.where(user_id: inbox.inbox_members.select(:user_id))
    account_users.each do |member|
      reason = rules.agent_reason(member, online_ids: presence[:user_ids])
      reason ||= 'capacity_reached' if human_policy &&
                                      inbox.account.conversations.open.where(assignee_id: member.user_id).count >= human_policy[:max_open]
      reason ||= 'rate_limit_reached' if configuration_reason.nil? && !human_policy && inbox.auto_assignment_v2_enabled? &&
                                        !AutoAssignment::RateLimiter.new(inbox: inbox, agent: member.user).within_limit?
      counts[reason || 'eligible'] += 1
    end
    reason = configuration_reason || rules.conversation_reason || presence[:reason]
    reason ||= 'conversation_not_requested' if conversation && conversation.auto_assignment_requested_at.nil?
    reason ||= presence[:user_ids].empty? ? 'no_online_agents' : 'no_eligible_agents' if counts['eligible'].zero?
    {
      reason: reason || 'ready',
      assignment_v2: inbox.auto_assignment_v2_enabled?,
      policy_configured: inbox.assignment_policy.present?,
      effective_online_agents: presence[:user_ids].size,
      agent_reasons: counts,
      pending_new_events: inbox.conversations.open.unassigned.where.not(auto_assignment_requested_at: nil).count
    }
  rescue Redis::BaseError
    { reason: 'redis_presence_unavailable', agent_reasons: {}, effective_online_agents: 0 }
  end
end
