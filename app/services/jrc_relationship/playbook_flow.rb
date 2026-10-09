# Prepares a reviewed native FlowRun; JrcFlows::Runner remains the only executor.
class JrcRelationship::PlaybookFlow
  INTERNAL_NODES = %w[start variable condition switch input delay note message media webhook status labels assign contact create_lead move_deal activity nico end].freeze
  STAMP_KEY = '_relationship_playbook'.freeze

  def initialize(context)
    @context = context
  end

  def self.definition_digest(flow)
    JrcRelationship::PlaybookFlowReference.definition_digest(flow)
  end

  def self.catalog(context)
    fresh = JrcRelationship::Context.new(context.member)
    return [] unless fresh.policy.admin? && JrcFlows::Access.enabled?(fresh.account)

    authors = fresh.account.account_users.where(role: 'administrator').select(:user_id)
    JrcFlow.active.where(account_id: fresh.account.id, created_by_id: authors, connection_id: nil, engine: 'native').order(:id).map do |flow|
      { 'id' => flow.id, 'name' => flow.name, 'flow_lock_version' => flow.lock_version, 'flow_digest' => definition_digest(flow),
        'local' => flow.connection_id.nil?, 'keyword_required' => flow.settings['keyword'].present?,
        'business_hours' => flow.settings['business_hours'] == true }
    end
  end

  def self.visible_runs(context:, assignment:)
    JrcRelationship::PlaybookFlowVisibility.new(context: context, assignment: assignment).scope
  end

  def self.visible_run?(context:, assignment:, id:)
    JrcRelationship::PlaybookFlowVisibility.new(context: context, assignment: assignment).visible?(id)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    false
  end

  def projection(execution:)
    assignment = @context.assignment(execution.assignment_id)
    JrcRelationship::PlaybookFlowVisibility.new(context: @context, assignment: assignment).projection(execution)
  end

  def preview(assignment:, step:, source_key:, playbook: nil)
    reference = reference_for(assignment, step, source_key, playbook: playbook)
    dependencies = dependencies_for(reference)
    simulation = simulate(reference)
    result(reference).merge('state' => 'preview', 'status' => simulation&.fetch('status'),
                            'reason' => dependencies.first, 'dependencies' => dependencies,
                            'payload_digest' => reference.payload_digest, 'scope' => reference.scope, 'simulation' => simulation)
                     .merge(JrcRelationship::PlaybookFlowApproval.issue(reference) || {})
  end

  def call(assignment:, step:, source_key:, payload_digest:, **authorization)
    raise ArgumentError, 'Unknown flow authorization fields' if (authorization.keys - %i[execution approval_token]).any?

    execution = authorization[:execution]
    initial = reference_for(assignment, step, source_key, playbook: execution&.playbook)
    assignment.with_lock do
      JrcRelationship::PlaybookFlowLocks.acquire!(initial, execution: execution, exclusive_account: true)
      reference = reviewed_reference(assignment, step, source_key, execution, payload_digest)
      reference.conversation.with_lock do
        reference = reviewed_reference(assignment, step, source_key, execution, payload_digest)
        JrcRelationship::PlaybookFlowAdmission.new(reference).call(execution: execution, approval_token: authorization[:approval_token])
      end
    end
  end

  def self.native_settings(reference, execution: nil, approval_token: nil)
    stamp = reference.stamp
    stamp = stamp.merge('execution_id' => execution.id, 'approval_token' => approval_token) if execution
    reference.flow.settings.deep_dup.merge('_flow_version' => reference.flow.lock_version, STAMP_KEY => stamp)
  end

  private

  def reference_for(assignment, step, source_key, playbook: nil)
    JrcRelationship::PlaybookFlowReference.new(context: @context, assignment: assignment, step: step, source_key: source_key, playbook: playbook)
  end

  def reviewed_reference(assignment, step, source_key, execution, digest)
    reference = reference_for(assignment, step, source_key, playbook: execution&.playbook&.reload)
    existing = JrcFlowRun.where(account_id: @context.account.id, event_key: reference.event_key).first
    JrcRelationship::PlaybookFlowMutationJournal.new(existing).normalize_reference!(reference) if existing
    raise ArgumentError, 'Reviewed flow payload changed; preview again' unless digest == reference.payload_digest

    reference
  end

  def dependencies_for(reference)
    JrcRelationship::PlaybookFlowCapabilities.call(reference)
  end

  def simulate(reference)
    flow = reference.flow
    return if flow.connection_id

    raw = if flow.engine == 'native'
            JrcFlows::Simulator.new(flow, [], variables: reference.native_variables).perform
          else
            JrcFlows::WorkflowEngine.new(flow, simulation: true).perform({})
          end
    trace = Array(raw[:trace]).map { |entry| entry.stringify_keys.slice('node_id', 'type', 'waiting').merge('simulated' => true) }
    { 'status' => raw[:status], 'trace' => trace }
  end

  def result(reference)
    JrcRelationship::PlaybookFlowResult.reference(reference)
  end
end
