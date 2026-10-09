class JrcRelationship::PlaybookFlowContinuation
  JOURNAL_KEY = '_relationship_effects'.freeze

  def self.managed?(run)
    run.event_key.start_with?('relationship-playbook:') || run.settings.key?(JrcRelationship::PlaybookFlow::STAMP_KEY)
  end

  def self.perform(run, message: nil)
    return yield unless managed?(run)
    return run unless %w[running waiting delayed].include?(run.status)

    with_sources(run) do
      context = JrcRelationship::PlaybookFlowRunContext.new(run).authorize!
      authorized_message = context.authorize_message!(message)
      JrcRelationship::PlaybookFlowJournal.new(run).verify_outcomes!
      JrcRelationship::PlaybookFlowWebhookJournal.new(run).verify_outcomes!
      return run if JrcRelationship::PlaybookFlowWebhookJournal.new(run).pending?

      yield authorized_message
    end
  rescue JrcRelationship::PlaybookFlowSourceDenied, Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, ArgumentError, KeyError
    raise unless managed?(run)

    run.reload.update!(status: 'paused', error: 'playbook_flow_authorization_blocked', wake_at: nil, finished_at: Time.current)
    run
  end

  def self.with_sources(run)
    return yield unless managed?(run)

    JrcFlowRun.transaction do
      lock_sources!(run)
      yield
    end
  end

  def self.lock_sources!(run)
    initial = JrcRelationship::PlaybookFlowRunContext.new(run.reload)
    JrcRelationship::PlaybookFlowLocks.acquire!(initial.reference, execution: initial.execution)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, ArgumentError, KeyError
    raise JrcRelationship::PlaybookFlowSourceDenied, 'playbook_flow_source_authorization_blocked'
  end

  def self.authorize_node!(run, node)
    return unless managed?(run)

    context = JrcRelationship::PlaybookFlowRunContext.new(run).authorize!
    context.authorize_node!(node)
    JrcRelationship::PlaybookFlowJournal.new(run).verify_outcomes!
    JrcRelationship::PlaybookFlowWebhookJournal.new(run).verify_outcomes!
  end

  def self.effect(run, type, data, &)
    return yield unless managed?(run)

    context = JrcRelationship::PlaybookFlowRunContext.new(run).authorize!
    authorize_effect!(context.reference, run, type, data)

    if JrcRelationship::PlaybookFlowPolicy::MUTATIONS.key?(type)
      JrcRelationship::PlaybookFlowMutationGuard.new(context.reference).authorize!(type, data)
      return JrcRelationship::PlaybookFlowMutationJournal.new(run).effect(reference: context.reference, type: type, data: data, &)
    end
    if JrcRelationship::PlaybookFlowPolicy::DELIVERY_EFFECTS.include?(type)
      JrcRelationship::PlaybookFlowDeliveryGuard.new(context.reference).authorize!(type, data)
      return JrcRelationship::PlaybookFlowWebhookJournal.new(run).enqueue!(data) if type == 'webhook'
    end
    return yield unless %w[note message media].include?(type)
    raise ArgumentError, 'playbook_flow_effect_not_approved' unless context.reference.policy.effect_allowed?(type)

    JrcRelationship::PlaybookFlowJournal.new(run).effect(&)
  end

  def self.authorize_effect!(reference, run, type, data)
    node = reference.flow.graph.fetch('nodes').find { |item| item['id'] == run.node_id }
    raise ArgumentError, 'playbook_flow_effect_payload_changed' unless node && node.values_at('type', 'data') == [type, data]
    raise ArgumentError, 'playbook_flow_effect_not_approved' unless JrcRelationship::PlaybookFlow::INTERNAL_NODES.include?(type)
  end

  def self.delivery_allowed?(run)
    return true unless managed?(run)

    JrcRelationship::PlaybookFlowRunContext.new(run).authorize!
    JrcRelationship::PlaybookFlowJournal.new(run).verify_integrity!
    JrcRelationship::PlaybookFlowWebhookJournal.new(run).verify_integrity!
    true
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, ArgumentError, KeyError
    false
  end

  def self.resume_job(run)
    managed?(run) ? JrcRelationship::PlaybookFlowResumeJob : JrcFlows::ResumeJob
  end

  def self.error_message(run, error)
    managed?(run) ? 'playbook_flow_execution_failed' : error.message.to_s.first(240)
  end
end
