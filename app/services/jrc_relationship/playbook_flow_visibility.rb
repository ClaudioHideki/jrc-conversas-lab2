class JrcRelationship::PlaybookFlowVisibility
  def initialize(context:, assignment:)
    @context = JrcRelationship::Context.new(context.member)
    @assignment = @context.assignment(assignment.id)
  end

  def scope
    return JrcFlowRun.none unless enabled? && active_unit?

    native_runs
      .where("settings -> ? ->> 'assignment_id' = ?", stamp_key, @assignment.id.to_s)
      .where("settings -> ? ->> 'account_user_id' = ?", stamp_key, @context.member.id.to_s)
      .where("settings -> ? -> 'business_unit_id' = ?::jsonb", stamp_key, @assignment.business_unit_id.to_json)
      .where("settings -> ? ->> 'conversation_id' = conversation_id::text", stamp_key)
      .where("settings -> ? ->> 'contact_id' = (SELECT contact_id::text FROM conversations " \
             'WHERE conversations.id = jrc_flow_runs.conversation_id)', stamp_key)
      .where('EXISTS (SELECT 1 FROM jrc_flows JOIN conversations ON conversations.id = jrc_flow_runs.conversation_id ' \
             "WHERE jrc_flows.id = jrc_flow_runs.flow_id AND jrc_flow_runs.settings ->> '_flow_version' = jrc_flows.lock_version::text " \
             "AND jrc_flows.settings -> 'inbox_ids' @> jsonb_build_array(conversations.inbox_id))")
  end

  def visible?(id)
    run = scope.find_by(id: id)
    return false unless run

    if run.settings.fetch(stamp_key)['execution_id']
      JrcRelationship::PlaybookFlowRunContext.new(run).authorize_history!
      return true
    end
    legacy_binding?(run)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, ArgumentError, KeyError
    false
  end

  def projection(execution)
    raise Pundit::NotAuthorizedError unless execution.account_id == @context.account.id

    Array(execution.snapshot['results']).filter_map { |result| project_result(execution, result) }
  end

  private

  def native_runs
    JrcFlowRun.where(account_id: @context.account.id, flow_id: flows.select(:id), conversation_id: conversations.select(:id))
  end

  def stamp_key
    JrcRelationship::PlaybookFlow::STAMP_KEY
  end

  def enabled?
    @context.policy.admin? && JrcFlows::Access.enabled?(@context.account)
  end

  def active_unit?
    !@assignment.business_unit_id || JrcCrm::BusinessUnit.active.where(account_id: @context.account.id).exists?(@assignment.business_unit_id)
  end

  def flows
    authors = @context.account.account_users.where(role: 'administrator').select(:user_id)
    JrcFlow.active.where(account_id: @context.account.id, created_by_id: authors, connection_id: nil, engine: 'native')
  end

  def conversations
    contacts = @context.account.contacts
    contacts = @assignment.contact_id ? contacts.where(id: @assignment.contact_id) : contacts.where(company_id: @assignment.company_id)
    native = JrcCustomers::Visibility.new(account: @context.account, user: @context.user, account_user: @context.member)
    native.conversations.where(contact_id: contacts.select(:id))
  end

  def legacy_binding?(run)
    stamp = run.settings.fetch(stamp_key)
    reference = JrcRelationship::PlaybookFlowReference.new(context: @context, assignment: @assignment,
                                                           step: stamp.fetch('step'), source_key: stamp.fetch('source_key'))
    run.flow_id == reference.flow.id && run.event_key == reference.event_key && run.graph == reference.flow.graph &&
      run.settings == JrcRelationship::PlaybookFlow.native_settings(reference)
  end

  def project_result(execution, result)
    run = scope.where("settings -> ? ->> 'execution_id' = ?", stamp_key, execution.id.to_s)
               .where("settings -> ? ->> 'source_key' = ?", stamp_key, result.fetch('step_key')).first
    return project_without_run(execution, result) unless run
    return unless visible?(run.id)

    JrcRelationship::PlaybookFlowResult.run(run, step_key: result.fetch('step_key'))
  end

  def project_without_run(execution, result)
    native = JrcRelationship::PlaybookNativeResult.new(context: @context, assignment: @assignment)
    return native.project(execution: execution, result: result) if native.native_step?(execution: execution, result: result)

    decision = JrcRelationship::PlaybookFlowDecision.for_execution(execution, result.fetch('step_key')).first
    return result.except('approval_token') unless decision

    step = execution.snapshot.fetch('steps').find { |item| item['kind'] == 'flow' && item['step_key'] == decision.to_value.fetch('native_step_key') }
    reference = JrcRelationship::PlaybookFlowReference.new(context: @context, assignment: @assignment, step: step,
                                                           source_key: result.fetch('step_key'), playbook: execution.playbook)
    JrcRelationship::PlaybookFlowDecision.previous(reference, execution).merge('step_key' => result.fetch('step_key'))
  end
end
