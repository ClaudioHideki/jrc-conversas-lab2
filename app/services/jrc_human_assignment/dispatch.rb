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

    route_team!
    policy = JrcHumanAssignment::Policy.connection_for(@account, @conversation.inbox_id)
    return true if policy && policy['mode'] == 'direct' && eligible_destination?
    return false unless eligible?

    assign_selected_agent
  end

  def ready_for_dispatch?
    @account.active? && JrcHumanAssignment::Policy.enabled_for?(@account, @conversation.inbox_id) &&
      @conversation.auto_assignment_requested_at.present? && @conversation.inbox.account_id == @account.id && awaiting_human?
  end

  def request_predates_policy?
    policy = JrcHumanAssignment::Policy.connection_for(@account, @conversation.inbox_id)
    policy && policy['effective_from'] && @conversation.auto_assignment_requested_at < Time.iso8601(policy['effective_from'])
  end

  def assign_selected_agent
    selected = select_agent
    return false unless selected

    member = @account.account_users.find_by(user_id: selected)
    return false unless member && assign_member!(member, selected)

    JrcHumanAssignment::Policy.record_cursor!(@account, @conversation.inbox_id, agent_id: selected, team_id: @conversation.team_id)
    true
  end

  def assign_member!(member, selected)
    member.with_lock do
      @conversation.reload
      @account.reload
      next false unless member_assignable?(member, selected)

      @conversation.update!(assignee_id: selected)
      true
    end
  end

  def member_assignable?(member, selected)
    rules = AutoAssignment::Eligibility.new(inbox: @conversation.inbox.reload, conversation: @conversation)
    eligible? && rules.conversation_reason.nil? && rules.agent_reason(member).nil? &&
      eligible_agent_ids.include?(selected) && below_capacity?(selected)
  end

  def below_capacity?(selected)
    policy = JrcHumanAssignment::Policy.effective(@account, @conversation.inbox_id)
    @account.conversations.open.where(assignee_id: selected).count < policy[:max_open]
  end

  def route_team!
    policy = JrcHumanAssignment::Policy.connection_for(@account, @conversation.inbox_id)
    return unless policy && @conversation.team_id.nil?

    teams = @account.teams.where(id: policy['team_ids'], allow_auto_assign: true).index_by(&:id)
    ordered = ordered_teams(policy, teams)
    selected = policy['mode'] == 'direct' ? ordered.first : select_team_with_capacity(policy, teams, ordered)
    @conversation.update!(team: selected) if selected
  end

  def ordered_teams(policy, teams)
    ordered = policy['team_ids'].filter_map { |id| teams[id] }
    return ordered unless policy['mode'] == 'round_robin'

    cursor = ordered.index { |team| team.id == policy['last_team_id'] }
    cursor ? ordered.rotate(cursor + 1) : ordered
  end

  def select_team_with_capacity(policy, teams, ordered)
    ids = available_agent_ids
    loads = agent_loads(ids)
    ids = ids.select { |id| loads.fetch(id, 0) < policy['max_open'] }
    eligible_teams = TeamMember.where(team_id: teams.keys, user_id: ids).distinct.pluck(:team_id)
    ordered.find { |team| eligible_teams.include?(team.id) } || ordered.first
  end

  def agent_loads(ids)
    @account.conversations.open.where(assignee_id: ids).group(:assignee_id).count
  end

  def select_agent
    policy = JrcHumanAssignment::Policy.effective(@account, @conversation.inbox_id)
    ids = eligible_agent_ids
    loads = agent_loads(ids)
    ids = ids.select { |id| loads.fetch(id, 0) < policy[:max_open] }
    minimum = ids.map { |id| loads.fetch(id, 0) }.min
    candidates = ids.select { |id| loads.fetch(id, 0) == minimum }.sort
    candidates.find { |id| id > policy[:last_agent_id] } || candidates.first
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
    ids = @account.account_users.online.where(auto_assignment_enabled: true, user_id: online_ids).pluck(:user_id) &
          @conversation.inbox.member_ids_with_assignment_capacity
    if @account.feature_enabled?('jrc_contact_center')
      pending = JrcContactCenter::Qualification.pending.where(account_id: @account.id).joins(:account_user).pluck('account_users.user_id')
      ids -= pending
    end
    ids
  end

  def eligible_agent_ids
    available_agent_ids & @conversation.team.members.ids
  end
end
