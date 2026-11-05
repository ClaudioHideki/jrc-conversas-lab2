# A trend is a comparison with an actual authorized observation in the configured
# window, never an invented zero or another user's cached score.
class JrcRelationship::HealthTrend
  def initialize(context:, assignment:, configuration:)
    @context = context
    @assignment = assignment
    @configuration = configuration
  end

  def call(health)
    days = @configuration.effective_rules.fetch('health_trend_window_days')
    unavailable = { state: health[:score].nil? ? 'unavailable' : 'insufficient', window_days: days }
    return { trend: unavailable, source_ids: {} } if health[:score].nil?

    baseline = snapshots.where(calculated_at: days.days.ago..Time.current).where.not(score: nil).order(:calculated_at, :id).first
    return { trend: unavailable, source_ids: {} } unless baseline

    compare(baseline, health, days)
  end

  private

  def compare(baseline, health, days)
    current = health.merge(config_scope_key: @configuration.scope_key, config_version: @configuration.version)
    change = JrcRelationship::HealthChange.call(previous: baseline.attributes.symbolize_keys, current: current)
    direction = if change[:delta].zero?
                  'stable'
                else
                  (change[:delta].positive? ? 'improved' : 'declined')
                end
    { trend: change.merge(state: direction, window_days: days, baseline_at: baseline.calculated_at, baseline_snapshot_id: baseline.id),
      source_ids: baseline.signals.fetch('_source_ids', {}) }
  end

  def snapshots
    ids = @context.assignments.where(id: @assignment.id).select(:id)
    rows = JrcRelationship::HealthSnapshot.where(account: @context.account, assignment_id: ids,
                                                 viewer: @context.user, access_signature: @context.access_signature,
                                                 config_scope_key: @configuration.scope_key,
                                                 config_version: @configuration.version)
    JrcRelationship::SnapshotAccess.scope(@context, rows)
  end
end
