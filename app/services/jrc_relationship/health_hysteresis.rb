# Stabilizes recovery only. Deterioration and missing evidence are never delayed or hidden.
class JrcRelationship::HealthHysteresis
  BANDS = %w[critical risk attention healthy].freeze

  def self.band(score:, previous_band:, rules:)
    raw = JrcRelationship::HealthScore.band(score, rules: rules)
    return raw unless BANDS.include?(previous_band) && BANDS.include?(raw)
    return raw if BANDS.index(raw) <= BANDS.index(previous_band)

    margin = rules.fetch('health_hysteresis_points', 0)
    boundaries = [rules.fetch('critical_threshold', 40), rules.fetch('risk_threshold', 60), rules.fetch('healthy_threshold', 80)]
    recovered = boundaries.count { |threshold| score >= threshold + margin }
    BANDS[[recovered, BANDS.index(previous_band)].max]
  end

  def initialize(context:, assignment:)
    @context = context
    @assignment = assignment
    @configuration = context.configuration(assignment)
  end

  def call(health)
    rules = @configuration.effective_rules
    return [health, {}] if rules['health_hysteresis_points'].zero? || health[:score].nil?

    previous = previous_snapshot
    return [health, {}] unless previous&.score

    stable = self.class.band(score: health[:score], previous_band: previous.band, rules: rules)
    result = health.merge(raw_band: health[:band], band: stable,
                          hysteresis: { points: rules['health_hysteresis_points'], previous_band: previous.band,
                                        previous_snapshot_id: previous.id, retained: stable != health[:band] })
    [result, previous.signals.fetch('_source_ids', {})]
  end

  private

  def previous_snapshot
    visible_ids = @context.assignments.where(id: @assignment.id).select(:id)
    rows = JrcRelationship::HealthSnapshot.where(account: @context.account, assignment_id: visible_ids, viewer: @context.user,
                                                 config_scope_key: @configuration.scope_key, config_version: @configuration.version,
                                                 access_signature: @context.access_signature)
    JrcRelationship::SnapshotAccess.scope(@context, rows).order(calculated_at: :desc, id: :desc).first
  end
end
