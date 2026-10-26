class JrcHumanAssignment::Dispatch
  def initialize(conversation)
    @conversation = Conversation.where(account_id: conversation.account_id).find(conversation.id)
    @account = @conversation.account
  end

  def perform
    # Short transaction: serialize capacity decisions across inboxes of this tenant.
    @account.with_lock do
      @conversation.with_lock do
        next false unless eligible?

        selected = select_agent
        next false unless selected

        member = @account.account_users.find_by(user_id: selected)
        next false unless member

        assigned = member.with_lock do
          @conversation.reload
          @account.reload
          rules = AutoAssignment::Eligibility.new(inbox: @conversation.inbox.reload, conversation: @conversation)
          next false unless eligible? && rules.conversation_reason.nil? && rules.agent_reason(member).nil? && eligible_agent_ids.include?(selected)

          policy = JrcHumanAssignment::Policy.for(@account)
          next false if @account.conversations.open.where(assignee_id: selected).count >= policy[:max_open]

          @conversation.update!(assignee_id: selected)
          true
        end
        next false unless assigned
        settings = @account.custom_attributes.fetch('jrc_human_assignment')
        @account.update!(custom_attributes: @account.custom_attributes.merge(
          'jrc_human_assignment' => settings.merge('last_agent_id' => selected)
        ))
        true
      end
    end
  end

  private

  def select_agent
    policy = JrcHumanAssignment::Policy.for(@account)
    ids = eligible_agent_ids
    if @account.feature_enabled?('jrc_contact_center')
      pending_agent_ids = JrcContactCenter::Qualification.pending.where(account_id: @account.id)
                                               .joins(:account_user).pluck('account_users.user_id')
      ids -= pending_agent_ids
    end
    loads = @account.conversations.open.where(assignee_id: ids).group(:assignee_id).count
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
    @conversation.team&.account_id == @account.id && @conversation.team.allow_auto_assign? &&
      @conversation.inbox.account_id == @account.id
  end

  def awaiting_human?
    @conversation.open? && @conversation.assignee_id.nil? && @conversation.assignee_agent_bot_id.nil? &&
      @conversation.custom_attributes['nico_control'] != 'active' &&
      !JrcFlowRun.live.exists?(account_id: @account.id, conversation_id: @conversation.id)
  end

  def eligible_agent_ids
    available = OnlineStatusTracker.effective_available_users(@account.id)
    online_ids = available.select { |_id, state| state == 'online' }.keys.map(&:to_i)
    @account.account_users.online.where(auto_assignment_enabled: true, user_id: online_ids).pluck(:user_id) &
      @conversation.inbox.member_ids_with_assignment_capacity &
      @conversation.team.members.ids
  end
end
