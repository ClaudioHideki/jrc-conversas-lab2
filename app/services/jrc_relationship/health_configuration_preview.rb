# Draft what-if evaluation only. Uses native source scopes and health engine;
# never invokes Processor, playbooks, delivery or configuration persistence.
class JrcRelationship::HealthConfigurationPreview
  def initialize(context)
    @context = context
  end

  def call(assignment_id:, scope_key:, version:, weights:, rules:)
    JrcRelationship::Assignment.transaction do
      authority.call do |current|
        current.authorize_configuration_scope!(scope_key)
        assignment = current.assignment(assignment_id)
        draft = draft_configuration(current, scope_key, version, weights, rules)
        proposed = current.for_health_configuration_preview(draft)
        { simulation: true, business_writes_performed: false, evaluated_at: Time.current,
          customer: { id: assignment.id, name: assignment.label },
          current: evaluate(current, assignment), proposed: evaluate(proposed, assignment),
          draft_effective: proposed.configuration(assignment).equal?(draft) }
      end
    end
  end

  private

  def authority
    JrcRelationship::BatchReviewAuthority.new(account_id: @context.account.id, actor_id: @context.user.id, write: false)
  end

  def draft_configuration(context, scope_key, version, weights, rules)
    existing = JrcRelationship::Configuration.find_or_initialize_by(account: context.account, scope_key: scope_key)
    raise ActiveRecord::StaleObjectError.new(existing, 'preview') unless Integer(version.to_s, 10) == existing.version

    # Keep its native identity so uniqueness validation models an actual update.
    # This separate in-memory instance is never saved.
    draft = existing
    draft.assign_attributes(version: existing.version + 1, weights: weights, rules: rules)
    raise ActiveRecord::RecordInvalid, draft unless draft.valid?

    draft
  end

  def evaluate(context, assignment)
    configuration = context.configuration(assignment)
    signals = JrcRelationship::CustomerSignals.new(context: context, assignment: assignment).call
    { health: signals.fetch(:health), scope_key: configuration.scope_key, version: configuration.version }
  end
end
