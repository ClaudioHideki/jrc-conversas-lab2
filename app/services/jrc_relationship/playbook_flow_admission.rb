# Native admission and replay checks only; every effect is still executed by JrcFlows::Runner.
class JrcRelationship::PlaybookFlowAdmission
  def initialize(reference)
    @reference = reference
  end

  def call(execution:, approval_token:)
    @execution = execution
    previous = existing_result(execution, approval_token)
    return previous if previous

    dependencies = JrcRelationship::PlaybookFlowCapabilities.call(@reference)
    return blocked(dependencies.first, dependencies: dependencies) if dependencies.any?
    return blocked('playbook_flow_native_origin_required') unless execution

    JrcRelationship::PlaybookFlowOrigin.authorize!(@reference, execution)
    token = approval_for(approval_token)
    return blocked('explicit_flow_approval_required') unless token

    reason = authorization_reason(token)
    return blocked(reason) if reason
    return blocked('native_conversation_live_run_exists') if JrcFlowRun.live.exists?(conversation_id: @reference.conversation.id)

    perform_native(execution, token)
  end

  private

  def existing_result(execution, approval_token)
    previous = JrcRelationship::PlaybookFlowDecision.previous(@reference, execution)
    return previous if previous

    existing = JrcFlowRun.where(account_id: @reference.context.account.id, event_key: @reference.event_key).first
    replay(existing, execution, approval_token) if existing
  end

  def blocked(reason, dependencies: [])
    value = result.merge('state' => 'blocked', 'reason' => reason, 'dependencies' => dependencies,
                         'native_step_key' => @reference.step.fetch('step_key'), 'payload_digest' => @reference.payload_digest)
    JrcRelationship::PlaybookFlowDecision.record!(@reference, @execution, value)
  end

  def result
    JrcRelationship::PlaybookFlowResult.reference(@reference)
  end

  def authorization_reason(token)
    JrcRelationship::PlaybookFlowApproval.verify!(@reference, token)
    @reference.policy.limit!
    nil
  rescue ArgumentError => e
    reasons = %w[playbook_flow_approval_invalid_or_expired playbook_flow_approval_binding_changed playbook_flow_approval_expired
                 playbook_flow_hourly_limit]
    reasons.include?(e.message) ? e.message : 'playbook_flow_approval_or_limit_blocked'
  end

  def perform_native(execution, token)
    settings = JrcRelationship::PlaybookFlow.native_settings(@reference, execution: execution, approval_token: token)
    run = @reference.flow.runs.create!(account: @reference.context.account, conversation: @reference.conversation,
                                       event_key: @reference.event_key, graph: @reference.flow.graph.deep_dup,
                                       settings: settings,
                                       variables: native_variables, node_id: initial_node_id, last_message_id: @reference.input_message&.id || 0)
    JrcFlows::Runner.new(run).perform
    result.merge(JrcRelationship::PlaybookFlowResult.run(run.reload).except('step_key'), 'replayed' => false)
  end

  def initial_node_id
    @reference.flow.graph.fetch('nodes').find { |node| node['type'] == 'start' }.fetch('id')
  end

  def replay(run, execution, approval_token)
    token = run.settings.dig(JrcRelationship::PlaybookFlow::STAMP_KEY, 'approval_token')
    JrcRelationship::PlaybookFlowApproval.verify!(@reference, approval_token) if approval_token
    JrcRelationship::PlaybookFlowOrigin.authorize!(@reference, execution)
    expected = JrcRelationship::PlaybookFlow.native_settings(@reference, execution: execution, approval_token: token)
    actual = run.settings.except(JrcRelationship::PlaybookFlowContinuation::JOURNAL_KEY, JrcRelationship::PlaybookFlowMutationJournal::KEY,
                                JrcRelationship::PlaybookFlowWebhookJournal::KEY)
    valid = run.flow_id == @reference.flow.id && run.conversation_id == @reference.conversation.id && run.graph == @reference.flow.graph
    raise ArgumentError, 'Native playbook origin was reused with a different payload' unless valid && actual == expected

    result.merge(JrcRelationship::PlaybookFlowResult.run(run).except('step_key'), 'replayed' => true)
  end

  def approval_for(token)
    return token if token.present?
    return if @reference.policy.definition.fetch('approval_required')

    JrcRelationship::PlaybookFlowApproval.issue(@reference)&.fetch('approval_token')
  end

  def native_variables
    @reference.native_variables
  end
end
