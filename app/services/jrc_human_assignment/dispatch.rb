class JrcHumanAssignment::Dispatch
  def initialize(conversation)
    @conversation = Conversation.where(account_id: conversation.account_id).find(conversation.id)
    @account = @conversation.account
  end

  def perform
    # Short transaction: serialize capacity decisions across inboxes of this tenant.
    @account.with_lock do
      @conversation.with_lock { dispatch_locked }
    end
  end

  private

  def dispatch_locked
    return false unless ready_for_dispatch?
    return false if request_predates_policy?

    policy = JrcHumanAssignment::Policy.connection_for(@account, @conversation.inbox_id)
    return apply_fallback!(policy, 'outside_hours') if policy && policy['schedule'] == 'inbox' && @conversation.inbox.out_of_office?

    route_team!
    return true if policy && policy['mode'] == 'direct' && eligible_destination?
    return apply_fallback!(policy, 'no_eligible_agent') unless eligible?

    assign_selected_agent || apply_fallback!(policy, 'no_eligible_agent')
  end

  def ready_for_dispatch?
    @account.active? && JrcHumanAssignment::Policy.enabled_for?(@account, @conversation.inbox_id) &&
      @conversation.auto_assignment_requested_at.present? && @conversation.inbox.account_id == @account.id && awaiting_human?
  end

  def request_predates_policy?
    policy = JrcHumanAssignment::Policy.connection_for(@account, @conversation.inbox_id)
    since = policy && (policy['requests_since'] || policy['effective_from'])
    since && @conversation.auto_assignment_requested_at < Time.iso8601(since)
  end

  def assign_selected_agent
    selected = select_agent
    return false unless selected

    preferred = @conversation.custom_attributes['jrc_preferred_agent_id'] == selected
    requested_at = @conversation.auto_assignment_requested_at.iso8601(6)
    member = @account.account_users.find_by(user_id: selected)
    return false unless member && assign_member!(member, selected)

    record_decision!(selected, preferred, requested_at)
    JrcHumanAssignment::Policy.record_cursor!(@account, @conversation.inbox_id, agent_id: selected, team_id: @conversation.team_id)
    true
  end

  def assign_member!(member, selected)
    member.with_lock do
      @conversation.reload
      @account.reload
      next false unless member_assignable?(member, selected)

      @conversation.update!(assignee_id: selected, custom_attributes: @conversation.custom_attributes.except('jrc_preferred_agent_id'))
      true
    end
  end

  def member_assignable?(member, selected)
    rules = AutoAssignment::Eligibility.new(inbox: @conversation.inbox.reload, conversation: @conversation)
    respect = JrcHumanAssignment::Policy.effective(@account, @conversation.inbox_id)[:respect_availability] != false
    eligible? && rules.conversation_reason.nil? && rules.agent_reason(member, respect_availability: respect).nil? &&
      eligible_agent_ids.include?(selected) && below_capacity?(selected)
  end

  def below_capacity?(selected)
    workload.available([selected]).include?(selected)
  end

  def record_decision!(selected, preferred, requested_at)
    return unless JrcHumanAssignment::Policy.effective(@account, @conversation.inbox_id)[:visibility] == 'assigned_only'

    count = workload.loads([selected]).fetch(selected, 0)
    JrcBrokerConnectionEvent.create!(account: @account, inbox: @conversation.inbox, user_id: selected,
                                     event_type: 'DISTRIBUTION_ASSIGNED', occurred_at: Time.current,
                                     metadata: { conversation_id: @conversation.id, agent_id: selected, team_id: @conversation.team_id,
                                                 active_count: count, capacity_limit: workload.limit(selected),
                                                 reason: preferred ? 'eligible_preferred_agent' : 'lowest_occupancy_round_robin',
                                                 requested_at: requested_at })
  end

  def route_team!
    policy = JrcHumanAssignment::Policy.connection_for(@account, @conversation.inbox_id)
    return unless policy && @conversation.team_id.nil?

    teams = @account.teams.where(id: policy['team_ids'], allow_auto_assign: true).index_by(&:id)
    ordered = ordered_teams(policy, teams)
    selected = policy['mode'] == 'direct' ? ordered.first : select_team_with_capacity(teams, ordered)
    @conversation.update!(team: selected) if selected
  end

  def ordered_teams(policy, teams)
    ordered = policy['team_ids'].filter_map { |id| teams[id] }
    return ordered unless policy['mode'] == 'round_robin'

    cursor = ordered.index { |team| team.id == policy['last_team_id'] }
    cursor ? ordered.rotate(cursor + 1) : ordered
  end

  def select_team_with_capacity(teams, ordered)
    ids = workload.available(available_agent_ids)
    eligible_teams = TeamMember.where(team_id: teams.keys, user_id: ids).distinct.pluck(:team_id)
    ordered.find { |team| eligible_teams.include?(team.id) }
  end

  def workload
    JrcHumanAssignment::Workload.new(account: @account, inbox_id: @conversation.inbox_id,
                                     policy: JrcHumanAssignment::Policy.effective(@account, @conversation.inbox_id))
  end

  def select_agent
    candidates = workload.available(eligible_agent_ids)
    previous = @conversation.custom_attributes['jrc_preferred_agent_id']
    return previous if previous && candidates.include?(previous)

    workload.select(candidates)
  end

  def eligible?
    @account.active? && JrcHumanAssignment::Policy.enabled_for?(@account, @conversation.inbox_id) &&
      @conversation.auto_assignment_requested_at.present? && awaiting_human? && eligible_destination?
  end

  def eligible_destination?
    policy = JrcHumanAssignment::Policy.connection_for(@account, @conversation.inbox_id)
    @conversation.team&.account_id == @account.id && @conversation.team.allow_auto_assign? &&
      @conversation.inbox.account_id == @account.id && (!policy || policy['team_ids'].include?(@conversation.team_id))
  end

  def awaiting_human?
    @conversation.open? && @conversation.assignee_id.nil? && @conversation.assignee_agent_bot_id.nil? &&
      @conversation.custom_attributes['nico_control'] != 'active' &&
      !JrcFlowRun.live.exists?(account_id: @account.id, conversation_id: @conversation.id)
  end

  def available_agent_ids
    available = OnlineStatusTracker.effective_available_users(@account.id)
    online_ids = available.select { |_id, state| state == 'online' }.keys.map(&:to_i)
    members = @account.account_users.where(auto_assignment_enabled: true)
    respect = JrcHumanAssignment::Policy.effective(@account, @conversation.inbox_id)[:respect_availability] != false
    members = members.online.where(user_id: online_ids) if respect
    capacity_ids = @conversation.inbox.member_ids_with_assignment_capacity(respect_availability: respect)
    ids = members.pluck(:user_id) & capacity_ids
    if @account.feature_enabled?('jrc_contact_center')
      pending = JrcContactCenter::Qualification.pending.where(account_id: @account.id).joins(:account_user).pluck('account_users.user_id')
      ids -= pending
    end
    ids
  end

  def eligible_agent_ids
    available_agent_ids & @conversation.team.members.ids
  end

  def apply_fallback!(policy, reason)
    return false unless policy

    fallback = policy.fetch('fallback', 'waiting')
    team = if fallback == 'default_team'
             @account.teams.find_by(id: policy['fallback_team_id'], allow_auto_assign: true)
           elsif fallback == 'waiting'
             @conversation.team || @account.teams.where(id: policy['team_ids'], allow_auto_assign: true).find_by(id: policy['team_ids'].first)
           end
    signature = { 'reason' => reason, 'fallback' => fallback, 'team_id' => team&.id, 'effective_from' => policy['effective_from'],
                  'requested_at' => @conversation.auto_assignment_requested_at.iso8601(6) }
    return false if @conversation.custom_attributes['jrc_assignment_fallback'] == signature

    @conversation.update!(team: team, auto_assignment_requested_at: fallback == 'waiting' ? @conversation.auto_assignment_requested_at : nil,
                          custom_attributes: @conversation.custom_attributes.merge('jrc_assignment_fallback' => signature))
    JrcBrokerConnectionEvent.create!(account: @account, inbox: @conversation.inbox, event_type: 'DISTRIBUTION_FALLBACK',
                                     occurred_at: Time.current, metadata: signature.merge('conversation_id' => @conversation.id))
    false
  end
end
