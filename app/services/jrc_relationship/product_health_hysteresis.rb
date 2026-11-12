# Uses the same recovery rule as customer health, with the exact product model
# and current native evidence scope. Shared customer factors remain shared.
class JrcRelationship::ProductHealthHysteresis
  def initialize(context:, assignment:, product_id:, configuration:)
    @context = context
    @assignment = assignment
    @product_id = product_id.to_s
    @configuration = configuration
    raise ArgumentError, 'Wrong product configuration account' unless configuration.account_id == context.account.id
  end

  def call(health)
    rules = @configuration.effective_rules
    return [health, {}] if rules['health_hysteresis_points'].zero? || health[:score].nil?

    previous = previous_snapshot
    measured = previous&.signals&.dig('product_health', @product_id)
    return [health, {}] unless measured && measured['score']

    stable = JrcRelationship::HealthHysteresis.band(score: health[:score], previous_band: measured['band'], rules: rules)
    result = health.merge(raw_band: health[:band], band: stable,
                          hysteresis: { points: rules['health_hysteresis_points'], previous_band: measured['band'],
                                        previous_snapshot_id: previous.id, retained: stable != health[:band] })
    [result, previous.signals.fetch('_source_ids', {})]
  end

  private

  def previous_snapshot
    assignments = @context.assignments.where(id: @assignment.id).select(:id)
    rows = JrcRelationship::HealthSnapshot.where(account: @context.account, assignment_id: assignments,
                                                 viewer: @context.user, access_signature: @context.access_signature)
                                          .where("signals -> 'product_health' -> ? ->> 'config_scope_key' = ?",
                                                 @product_id, @configuration.scope_key)
                                          .where("signals -> 'product_health' -> ? ->> 'config_version' = ?",
                                                 @product_id, @configuration.version.to_s)
    JrcRelationship::SnapshotAccess.scope(@context, rows).order(calculated_at: :desc, id: :desc).first
  end
end
