# Existing shared policies retain their account-wide cap. Central inboxes use
# individual per-inbox limits; comparing rationals avoids percentage rounding.
class JrcHumanAssignment::Workload
  def initialize(account:, inbox_id:, policy:)
    @account = account
    @inbox_id = inbox_id
    @policy = policy
  end

  def loads(ids)
    scope = @account.conversations.open.where(assignee_id: ids)
    scope = scope.where(inbox_id: @inbox_id) if exclusive?
    scope.group(:assignee_id).count
  end

  def limit(id)
    exclusive? ? @policy.fetch(:agent_limits, {}).fetch(id.to_s, @policy[:max_open]) : @policy[:max_open]
  end

  def available(ids)
    counts = loads(ids)
    ids.select { |id| @policy[:capacity_enabled] == false || counts.fetch(id, 0) < limit(id) }
  end

  def select(ids)
    ids = available(ids)
    counts = loads(ids)
    scores = ids.index_with { |id| exclusive? ? Rational(counts.fetch(id, 0), limit(id)) : counts.fetch(id, 0) }
    minimum = scores.values.min
    candidates = ids.select { |id| scores[id] == minimum }.sort
    candidates.find { |id| id > @policy.fetch(:last_agent_id, 0) } || candidates.first
  end

  private

  def exclusive?
    @policy[:visibility] == 'assigned_only'
  end
end
