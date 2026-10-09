class JrcRelationship::PlaybookFlowOrigin
  def self.authorize!(reference, execution)
    raise Pundit::NotAuthorizedError unless execution.is_a?(JrcRelationship::PlaybookExecution) && execution.persisted?

    current = JrcRelationship::PlaybookExecution.where(account_id: reference.context.account.id).find(execution.id)
    authorize_binding!(reference, current)
    version = reference.playbook.versions.find_by!(account_id: reference.context.account.id, version: current.version)
    authorize_snapshot!(reference, current, version)
    current
  end

  def self.authorize_binding!(reference, current)
    expected = [reference.assignment.id, reference.context.user.id, reference.playbook&.id, reference.playbook&.version]
    actual = current.attributes.values_at('assignment_id', 'actor_id', 'playbook_id', 'version')
    raise Pundit::NotAuthorizedError unless actual == expected && reference.published_playbook?
  end

  def self.authorize_snapshot!(reference, current, version)
    raise ArgumentError, 'playbook_flow_origin_changed' unless current.snapshot.except('results') == version.payload
    raise ArgumentError, 'playbook_flow_step_origin_changed' unless current.step_source_keys.include?(reference.source_key)
    raise ArgumentError, 'playbook_flow_step_not_published' unless version.payload.fetch('steps').include?(reference.step)
  end
end
