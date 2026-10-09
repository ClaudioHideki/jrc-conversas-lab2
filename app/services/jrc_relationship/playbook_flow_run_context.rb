class JrcRelationship::PlaybookFlowRunContext
  attr_reader :reference, :execution, :token

  def initialize(run)
    @run = run
    stamp = run.settings.fetch(JrcRelationship::PlaybookFlow::STAMP_KEY)
    @execution = JrcRelationship::PlaybookExecution.where(account_id: run.account_id).find(stamp.fetch('execution_id'))
    @reference = reference_from(stamp)
    @token = stamp.fetch('approval_token')
    JrcRelationship::PlaybookFlowMutationJournal.new(run).normalize_reference!(@reference)
  end

  def authorize!
    authorize_history!
    raise ArgumentError, reference.policy.reason if reference.policy.reason
    reasons = JrcRelationship::PlaybookFlowCapabilities.dispatch_dependencies(reference)
    raise ArgumentError, reasons.first if reasons.any?

    JrcRelationship::PlaybookFlowApproval.verify!(reference, token)
    reference.policy.limit!(run: @run)
    self
  end

  def authorize_history!
    JrcRelationship::PlaybookFlowOrigin.authorize!(reference, execution)
    verify_native_run!
    self
  end

  def authorize_message!(message)
    return unless message

    current = Message.where(account_id: @run.account_id, conversation_id: @run.conversation_id,
                             inbox_id: reference.conversation.inbox_id).lock('FOR SHARE').find(message.id)
    valid = current.incoming? && !current.private? && current.sender_type == 'Contact' && current.sender_id == reference.contact.id
    raise Pundit::NotAuthorizedError unless valid && current.content_attributes.to_h['jrc_flow_run_id'].blank?

    current
  end

  def authorize_node!(node)
    raise ArgumentError, 'playbook_flow_step_limit' if @run.steps >= reference.policy.definition.fetch('max_steps')
    raise ArgumentError, 'playbook_flow_node_payload_changed' unless reference.flow.graph.fetch('nodes').include?(node)

    type = node.fetch('type')
    if JrcRelationship::PlaybookFlowPolicy::MUTATIONS.key?(type)
      JrcRelationship::PlaybookFlowMutationGuard.new(reference).authorize!(type, node.fetch('data'))
    elsif JrcRelationship::PlaybookFlowPolicy::DELIVERY_EFFECTS.include?(type)
      JrcRelationship::PlaybookFlowDeliveryGuard.new(reference).authorize!(type, node.fetch('data'))
    elsif %w[note message].include?(type) && !reference.policy.effect_allowed?(type)
      raise ArgumentError, 'playbook_flow_effect_not_approved'
    end
  end

  private

  def reference_from(stamp)
    member = AccountUser.where(account_id: execution.account_id, user_id: execution.actor_id).find(stamp.fetch('account_user_id'))
    step = execution.snapshot.fetch('steps').find { |item| item['step_key'] == stamp.dig('step', 'step_key') }
    JrcRelationship::PlaybookFlowReference.new(context: JrcRelationship::Context.new(member), assignment: execution.assignment,
                                               step: step, source_key: stamp.fetch('source_key'), playbook: execution.playbook)
  end

  def verify_native_run!
    expected = JrcRelationship::PlaybookFlow.native_settings(reference, execution: execution, approval_token: token)
    valid = native_binding? && @run.settings.except(JrcRelationship::PlaybookFlowContinuation::JOURNAL_KEY,
                                                   JrcRelationship::PlaybookFlowMutationJournal::KEY,
                                                   JrcRelationship::PlaybookFlowWebhookJournal::KEY) == expected
    raise ArgumentError, 'playbook_flow_run_binding_changed' unless valid
  end

  def native_binding?
    [@run.flow_id, @run.conversation_id, @run.account_id, @run.event_key, @run.graph] ==
      [reference.flow.id, reference.conversation.id, execution.account_id, reference.event_key, reference.flow.graph]
  end
end
