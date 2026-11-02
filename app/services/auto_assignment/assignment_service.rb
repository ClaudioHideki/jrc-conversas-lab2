class AutoAssignment::AssignmentService
  pattr_initialize [:inbox!]

  def perform_bulk_assignment(limit: 100)
    return 0 if JrcHumanAssignment::Policy.enabled_for?(inbox.account, inbox.id)
    return 0 unless inbox.auto_assignment_v2_enabled?
    return 0 unless inbox.enable_auto_assignment?
    return 0 unless AutoAssignment::Eligibility.new(inbox: inbox).configuration_reason.nil?

    conversations = unassigned_conversations(limit).to_a
    return 0 if conversations.empty?
    return 0 if inbox.available_agents.empty?

    assigned_count = 0
    conversations.each do |conversation|
      assigned_count += 1 if perform_for_conversation(conversation)
    end
    assigned_count
  end

  private

  def perform_for_conversation(conversation)
    return false unless assignable?(conversation)

    agent = find_available_agent(conversation)
    return false unless agent

    assign_conversation(conversation, agent)
  end

  def assignable?(conversation)
    conversation.auto_assignment_requested_at.present? &&
      AutoAssignment::Eligibility.new(inbox: inbox, conversation: conversation).conversation_reason.nil?
  end

  def unassigned_conversations(limit)
    scope = inbox.conversations.unassigned.open.where.not(auto_assignment_requested_at: nil)

    # Skip stale backlog with no activity beyond the age threshold
    policy = inbox.assignment_policy
    scope = apply_age_exclusions(scope, age_exclusion_hours(policy))

    # Apply conversation priority using assignment policy if available
    scope = if policy&.longest_waiting?
              scope.reorder(last_activity_at: :asc, created_at: :asc)
            else
              scope.reorder(created_at: :asc)
            end

    scope.limit(limit)
  end

  def age_exclusion_hours(policy)
    return policy.exclude_older_than_hours if policy

    AssignmentPolicy::DEFAULT_EXCLUDE_OLDER_THAN_HOURS
  end

  def apply_age_exclusions(scope, hours_threshold)
    return scope if hours_threshold.blank?

    hours = hours_threshold.to_i
    return scope unless hours.positive?

    # Use last_activity_at so reopened/active conversations aren't excluded by their original created_at
    scope.where('conversations.last_activity_at >= ?', hours.hours.ago)
  end

  def find_available_agent(conversation = nil)
    agents = filter_agents_by_team(inbox.available_agents, conversation)
    return nil if agents.nil?

    agents = filter_agents_by_rate_limit(agents)
    return nil if agents.empty?

    round_robin_selector.select_agent(agents)
  end

  def filter_agents_by_team(agents, conversation)
    return agents if conversation&.team_id.blank?

    team = conversation.team
    return nil if team.blank? || team.allow_auto_assign.blank?

    team_member_ids = team.members.ids
    agents.where(user_id: team_member_ids)
  end

  def filter_agents_by_rate_limit(agents)
    blocked = if inbox.account.feature_enabled?('jrc_contact_center')
                JrcContactCenter::Qualification.pending.where(account_id: inbox.account_id).joins(:account_user).pluck('account_users.user_id')
              else
                []
              end
    agents.select do |agent_member|
      rate_limiter = build_rate_limiter(agent_member.user)
      !blocked.include?(agent_member.user_id) && rate_limiter.within_limit?
    end
  end

  def assign_conversation(conversation, agent)
    return false unless claim_and_assign(conversation, agent)

    conversation.reload
    dispatch_assignment_event(conversation, agent)
    true
  end

  # Atomically claim the row so two bulk runs that overlap (the in-flight gate
  # is best-effort and can lapse on TTL) can't both assign the same conversation.
  def claim_and_assign(conversation, agent)
    inbox.account.with_lock(requires_new: true) do
      if inbox.account.feature_enabled?('jrc_contact_center') &&
         JrcContactCenter::Qualification.pending.where(account_id: inbox.account_id).joins(:account_user)
                                       .exists?(account_users: { user_id: agent.id })
        next false
      end
      locked = inbox.conversations
                    .where(id: conversation.id, assignee_id: nil)
                    .lock('FOR UPDATE SKIP LOCKED')
                    .first
      next false unless locked
      next false if JrcHumanAssignment::Policy.enabled_for?(inbox.account.reload, inbox.id)
      member = inbox.account.account_users.find_by(user_id: agent.id)
      next false unless member

      member.with_lock do
        rules = AutoAssignment::Eligibility.new(inbox: inbox.reload, conversation: locked)
        next false unless inbox.auto_assignment_v2_enabled?
        next false unless rules.configuration_reason.nil? && assignable?(locked) && rules.agent_reason(member).nil?
        rate_limiter = build_rate_limiter(agent)
        next false unless rate_limiter.within_limit?
        # Enterprise exclusions and capacity are evaluated again under the tenant
        # lock so a competing inbox run cannot overbook the same agent.
        next false unless unassigned_conversations(1).where(id: locked.id).exists?

        Current.executed_by = inbox.assignment_policy
        locked.update!(assignee: agent)
        # Keep the reservation inside the account transaction. Redis failures
        # must roll the assignment back before another worker checks the limit.
        rate_limiter.track_assignment(locked)
        true
      end
    end
  ensure
    Current.executed_by = nil
  end

  def dispatch_assignment_event(conversation, agent)
    Rails.configuration.dispatcher.dispatch(
      Events::Types::ASSIGNEE_CHANGED,
      Time.zone.now,
      conversation: conversation,
      user: agent
    )
  end

  def build_rate_limiter(agent)
    AutoAssignment::RateLimiter.new(inbox: inbox, agent: agent)
  end

  def round_robin_selector
    @round_robin_selector ||= AutoAssignment::RoundRobinSelector.new(inbox: inbox)
  end
end

AutoAssignment::AssignmentService.prepend_mod_with('AutoAssignment::AssignmentService')
