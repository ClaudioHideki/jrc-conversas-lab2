# Append-only denial receipts use the existing native audit store; no execution snapshot is rewritten.
class JrcRelationship::PlaybookFlowDecision
  PURPOSE = 'relationship-playbook-flow-decision'.freeze
  ACTION = 'playbook_flow_blocked'.freeze

  def self.previous(reference, execution)
    return unless execution

    JrcRelationship::PlaybookFlowOrigin.authorize!(reference, execution)
    row = scope(reference, execution).first
    return unless row

    expected = binding(reference, execution, row.to_value)
    raise ArgumentError, 'playbook_flow_decision_binding_changed' unless verifier.verified(row.metadata.fetch('signature'),
                                                                                           purpose: PURPOSE) == expected

    row.to_value
  end

  def self.record!(reference, execution, result)
    return result unless execution

    previous = previous(reference, execution)
    return previous if previous

    JrcCustomers::Audit.record!(account: reference.context.account, actor: reference.context.user, resource: execution,
                                event_type: 'relationship_updated', to_value: result,
                                metadata: { action: ACTION, assignment_id: reference.assignment.id, step_key: reference.source_key,
                                            signature: verifier.generate(binding(reference, execution, result), purpose: PURPOSE) })
    result
  end

  def self.for_execution(execution, step_key)
    JrcCrm::AuditEvent.where(account_id: execution.account_id, resource_type: execution.class.name, resource_id: execution.id,
                             event_type: 'relationship_updated', actor_type: 'User', actor_id: execution.actor_id)
                      .where("metadata ->> 'action' = ? AND metadata ->> 'step_key' = ?", ACTION, step_key)
  end

  def self.scope(reference, execution)
    for_execution(execution, reference.source_key)
  end

  def self.binding(reference, execution, result)
    { 'account_id' => execution.account_id, 'execution_id' => execution.id, 'actor_id' => execution.actor_id,
      'step_key' => reference.source_key, 'scope' => reference.scope, 'result' => result }
  end

  def self.verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
