# Explicit account baseline: starts evidence now, never reconstructs prior dates.
class JrcRelationship::RetentionHistory
  def self.start!(context, reason:)
    raise ArgumentError, 'A reason is required' unless reason.is_a?(String) && reason.strip.length.between?(1, 2000)
    JrcRelationship::RetentionCoverage.transaction do
      JrcRelationship::BatchReviewAuthority.new(account_id: context.account.id, actor_id: context.user.id).call do |fresh|
        raise Pundit::NotAuthorizedError unless fresh.policy.admin? && fresh.policy.configure?
        connection = JrcRelationship::Assignment.connection
        account_id = Integer(fresh.account.id)
        connection.execute("SELECT pg_advisory_xact_lock(1280528947, #{account_id})")
        existing = JrcRelationship::RetentionCoverage.find_by(account_id: account_id)
        next({ started_at: existing.started_at, already_started: true }) if existing

        connection.execute("SELECT jrc_rel_retention_observe(to_jsonb(a), false, true) FROM jrc_relationship_assignments a WHERE a.account_id = #{account_id}")
        started_at = connection.select_value("SELECT timezone('UTC', clock_timestamp())")
        coverage = JrcRelationship::RetentionCoverage.create!(account_id: account_id, started_at: started_at)
        fresh.audit!(coverage, action: 'retention_history_started', after: { reason: reason.strip, started_at: coverage.started_at })
        { started_at: coverage.started_at, already_started: false }
      end
    end
  end
end
