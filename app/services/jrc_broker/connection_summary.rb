class JrcBroker::ConnectionSummary
  POLICY_FIELDS = %w[enabled mode team_ids max_open respect_availability capacity_enabled waiting_enabled schedule fallback fallback_team_id].freeze

  def initialize(binding:, manage:, reports:)
    @account = binding.account
    @inbox = binding.inbox
    @manage = manage
    @reports = reports
  end

  def perform
    policy = JrcHumanAssignment::Policy.connection_for(@account, @inbox.id)&.slice(*POLICY_FIELDS) if @manage
    { inbox_id: @inbox.id, name: @inbox.name, policy: policy, teams: selected_teams(policy), metrics: @reports ? metrics : nil }
  end

  private

  def selected_teams(policy)
    ids = policy&.fetch('team_ids', []) || []
    teams = @account.teams.where(id: ids).index_by(&:id)
    ids.filter_map do |id|
      team = teams[id]
      { id: team.id, name: team.name } if team
    end
  end

  def metrics
    until_time = Time.current.utc
    since_time = until_time - 30.days
    range = since_time..until_time
    events = @account.reporting_events.where(inbox_id: @inbox.id, created_at: range, name: %w[first_response conversation_resolved])
    averages = events.group(:name).average(:value)
    samples = events.group(:name).count
    {
      window: { since: since_time.iso8601, until: until_time.iso8601 },
      conversations_count: @account.conversations.where(inbox_id: @inbox.id, created_at: range).count,
      avg_first_response_time: averages['first_response'], avg_resolution_time: averages['conversation_resolved'],
      first_response_sample_count: samples.fetch('first_response', 0), resolution_sample_count: samples.fetch('conversation_resolved', 0),
      unit: 'seconds', eligible_agents: nil
    }
  end
end
