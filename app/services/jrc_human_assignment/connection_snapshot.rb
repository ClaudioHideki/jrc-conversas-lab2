class JrcHumanAssignment::ConnectionSnapshot
  def initialize(account:, inbox:)
    @account = account
    @inbox = inbox
  end

  def perform
    { policy: JrcHumanAssignment::Policy.connection_for(@account, @inbox.id), agents: agents, waiting: waiting,
      calendar: { enabled: @inbox.working_hours_enabled?, timezone: @inbox.timezone, weekly_schedule: @inbox.weekly_schedule },
      teams: @account.teams.where(allow_auto_assign: true).order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } } }
  end

  private

  def agents
    counts = @account.conversations.open.where(inbox_id: @inbox.id).group(:assignee_id).count
    members = @account.account_users.where(user_id: @inbox.members.select(:id)).index_by(&:user_id)
    @inbox.members.order(:name).map do |user|
      member = members.fetch(user.id)
      { id: user.id, name: user.name, active: counts.fetch(user.id, 0), availability: member.availability,
        can_supervise: member.custom_role_id.nil? || member.permissions.include?('conversation_manage') }
    end
  end

  def waiting
    @account.conversations.open.where(inbox_id: @inbox.id, assignee_id: nil, assignee_agent_bot_id: nil)
            .where.not(auto_assignment_requested_at: nil)
            .where.not(id: JrcFlowRun.live.where(account_id: @account.id).select(:conversation_id))
            .where("custom_attributes ->> 'nico_control' IS DISTINCT FROM ?", 'active').count
  end
end
