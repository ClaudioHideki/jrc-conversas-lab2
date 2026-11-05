require 'digest'

# Called under Processor's native assignment lock. Only an exact closed cause
# created by this engine is delayed; active actions and risk evaluation continue.
class JrcRelationship::AutomaticActionCooldown
  def self.digest(kind:, key:, data:)
    sources = data.fetch(:_source_ids, {}).to_h.transform_keys(&:to_s).transform_values { |ids| Array(ids).map(&:to_s).uniq.sort }
    family = %w[health health_drop].include?(kind) ? 'health' : kind
    health = data[:health].is_a?(Hash) ? data[:health].slice(:score, :band) : {}
    payload = { family: family, key: key, sources: sources, health: health }
    Digest::SHA256.hexdigest(JrcServiceDesk::CanonicalJson.normalize(payload).to_json)
  end

  def initialize(context:, assignment:, digest:, hours:)
    @context = context
    @assignment = assignment
    @digest = digest
    @hours = hours
  end

  def allow?
    return true if @hours.zero?

    @context = JrcRelationship::Context.new(@context.member)
    raise Pundit::NotAuthorizedError unless @context.user.active_for_authentication?

    @context.assignment(@assignment.id, write: true)
    previous = @assignment.actions.where(status: %w[completed dismissed])
                          .where("metadata ->> 'automatic_cause_digest' = ? AND metadata ->> 'automatic' = 'true'", @digest)
                          .order(Arel.sql('COALESCE(completed_at, updated_at) DESC, id DESC')).first
    return true unless previous

    closed_at = previous.completed_at || previous.updated_at
    return true if closed_at > Time.current || closed_at + @hours.hours <= Time.current

    audit_suppression!(previous, closed_at + @hours.hours)
    false
  end

  private

  def audit_suppression!(previous, until_at)
    key = Digest::SHA256.hexdigest([@digest, previous.id, @hours].join(':'))
    audit = JrcCrm::AuditEvent.where(account_id: @context.account.id, resource_type: @assignment.class.name,
                                     resource_id: @assignment.id, event_type: 'relationship_updated')
    audit = audit.where("metadata ->> 'action' = ? AND to_value ->> 'suppression_key' = ?", 'automatic_action_suppressed', key)
    return if audit.exists?

    @context.audit!(@assignment, action: 'automatic_action_suppressed', after: {
                      suppression_key: key, closed_action_id: previous.id, cooldown_hours: @hours, next_allowed_at: until_at,
                      reason: 'unchanged_closed_cause'
                    })
  end
end
