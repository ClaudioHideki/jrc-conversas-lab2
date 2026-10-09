require 'digest'

class JrcRelationship::Playbooks
  NATIVE_ACTIVITIES = %w[activity meeting].freeze
  WORKFLOW_STEPS = %w[success_plan risk].freeze

  def initialize(context)
    @context = context
  end

  def run!(assignment, trigger, source_key: 'handoff', playbook_id: nil, flow_approvals: {})
    @context.assignment(assignment.id, write: true)
    validate_handoff!(assignment, trigger)
    raise ArgumentError, 'Flow approvals must be an object' unless flow_approvals.is_a?(Hash)

    assignment.with_lock { execute!(assignment, trigger, source_key, playbook_id, flow_approvals.stringify_keys) }
  end

  private

  def validate_handoff!(assignment, trigger)
    return unless trigger == 'onboarded' && @context.configuration.effective_rules['handoff_acceptance_required']
    return if JrcRelationship::HandoffCase.exists?(account: @context.account, assignment: assignment,
                                                   source_type: 'JrcCrm::SalesOrder', status: 'accepted')

    raise ArgumentError, 'Formal handoff acceptance is required before onboarding'
  end

  def execute!(assignment, trigger, source_key, playbook_id, approvals)
    rows = selected_playbooks(assignment, trigger, source_key, playbook_id)
    executions = flow_executions(rows, assignment, source_key, approvals)
    steps = rows.flat_map { |book| book.steps.map.with_index { |step, index| [step_key(book, step, index, source_key), step, book] } }
    steps = onboarding_steps(source_key) if default_onboarding?(rows, trigger, playbook_id)
    steps.each do |key, step, book|
      execution_context = { trigger: trigger, start: trigger == 'onboarded' ? assignment.created_at : Time.current.beginning_of_day }
      if step['kind'] == 'flow'
        flow_step!(assignment, step, key, executions.fetch(book.id), approvals[key])
      else
        native_step!(assignment, step, key, execution_context)
      end
    end
    rows.each { |book| record_execution!(book, assignment, source_key) unless executions.key?(book.id) }
  end

  def selected_playbooks(assignment, trigger, source_key, playbook_id)
    rows = JrcRelationship::Playbook.where(account: @context.account, active: true, trigger_kind: trigger).to_a
    rows = rows.select { |row| row.id == playbook_id.to_i } if playbook_id
    if rows.any? { |row| row.conditions.present? }
      signals = JrcRelationship::CustomerSignals.new(assignment: assignment, context: @context).call
      rows = rows.select { |row| JrcRelationship::PlaybookConditions.match?(row.conditions, signals) }
    end
    rows.reject do |book|
      JrcRelationship::PlaybookExecution.exists?(account: @context.account, execution_key: execution_key(book, assignment, source_key))
    end
  end

  def default_onboarding?(rows, trigger, playbook_id)
    trigger == 'onboarded' && rows.empty? && !playbook_id &&
      !JrcRelationship::Playbook.exists?(account: @context.account, active: true, trigger_kind: trigger)
  end

  def onboarding_steps(source_key)
    JrcRelationship::PlaybookSteps.onboarding.map do |step|
      key = step['kind'] == 'activity' ? "onboarded:#{step['after_days']}" : "onboarded:#{step['kind']}"
      ["#{key}:#{source_key}", step, nil]
    end
  end

  def flow_executions(rows, assignment, source_key, approvals)
    rows.select { |book| book.steps.any? { |step| step['kind'] == 'flow' } }.to_h do |book|
      results = book.steps.map.with_index do |step, index|
        key = step_key(book, step, index, source_key)
        pending_step(assignment, book, step, key, approvals[key])
      end
      [book.id, record_execution!(book, assignment, source_key, results: results)]
    end
  end

  def pending_step(assignment, book, step, key, token)
    return { 'step_key' => key, 'state' => 'pending', 'reason' => 'native_execution_pending' } unless step['kind'] == 'flow'

    preview = JrcRelationship::PlaybookFlow.new(@context).preview(assignment: assignment, step: step, source_key: key, playbook: book)
    reason = preview['reason'] || ('explicit_flow_approval_required' if token.blank?)
    { 'step_key' => key, 'state' => reason ? 'blocked' : 'pending', 'reason' => reason,
      'flow_lock_version' => step['flow_lock_version'], 'flow_digest' => step['flow_digest'] }
  end

  def flow_step!(assignment, step, key, execution, token)
    adapter = JrcRelationship::PlaybookFlow.new(@context)
    preview = adapter.preview(assignment: assignment, step: step, source_key: key, playbook: execution.playbook)
    adapter.call(assignment: assignment, step: step, source_key: key, payload_digest: preview['payload_digest'],
                 execution: execution, approval_token: token)
  end

  def native_step!(assignment, step, key, execution_context)
    if NATIVE_ACTIVITIES.include?(step['kind'])
      activity_step!(assignment, step, key, execution_context[:start])
    elsif WORKFLOW_STEPS.include?(step['kind'])
      workflow_step!(assignment, step, key, execution_context[:start])
    else
      action_step!(assignment, step, key, execution_context)
    end
  end

  def activity_step!(assignment, step, key, start)
    return unless JrcOperations::Access.crm?(@context.member)

    JrcRelationship::Workflow.new(@context).activity!(assignment: assignment, title: step['title'],
                                                      due_at: start + step['after_days'].to_i.days,
                                                      kind: step['kind'] == 'meeting' ? 'meeting' : 'task', request_id: key)
  end

  def action_step!(assignment, step, key, execution_context)
    record = assignment.actions.find_or_initialize_by(source_key: key)
    return if record.persisted?

    record.assign_attributes(account: @context.account, owner: assignment.owner, reason: step['title'], kind: execution_context[:trigger],
                             due_at: execution_context[:start] + step['after_days'].to_i.days)
    JrcRelationship::OperationalRouting.new(@context).prepare!(record)
    record.save!
    JrcRelationship::Workflow.new(@context).project_action!(record)
    @context.audit!(record, action: 'playbook_action')
  end

  def record_execution!(book, assignment, source_key, results: nil)
    JrcRelationship::PlaybookExecution.create_or_find_by!(account: @context.account,
                                                          execution_key: execution_key(book, assignment, source_key)) do |execution|
      execution.assignment = assignment
      execution.playbook = book
      execution.actor = @context.user
      execution.version = book.version
      execution.source_key = source_key
      execution.snapshot = book.snapshot.merge('results' => results || native_results(book, assignment, source_key))
      execution.step_source_keys = book.steps.map.with_index { |step, index| step_key(book, step, index, source_key) }
    end
  end

  def native_results(book, assignment, source_key)
    book.steps.map.with_index do |step, index|
      key = step_key(book, step, index, source_key)
      native = native_result(assignment, step, key)
      { 'step_key' => key, 'state' => native ? 'planned' : 'blocked', 'resource_type' => native&.class&.name,
        'resource_id' => native&.id, 'activity_id' => native.try(:activity_id), 'reason' => native ? nil : 'native_permission_unavailable' }
    end
  end

  def native_result(assignment, step, key)
    if (NATIVE_ACTIVITIES + ['action']).include?(step['kind'])
      action_key = NATIVE_ACTIVITIES.include?(step['kind']) ? "activity:#{key}" : key
      assignment.actions.find_by(source_key: action_key)
    else
      model = step['kind'] == 'risk' ? JrcRelationship::RiskCase : JrcRelationship::SuccessPlan
      model.where(assignment: assignment).find_by("metadata ->> 'playbook_source_key' = ?", key)
    end
  end

  def step_key(book, step, index, source_key)
    "playbook:#{book.id}:v#{book.version}:#{step['step_key'].presence || index}:#{source_key}"
  end

  def execution_key(book, assignment, source_key)
    Digest::SHA256.hexdigest([assignment.id, book.id, book.version, source_key].join(':'))
  end

  def workflow_step!(assignment, step, key, start)
    rows = @context.records(step['kind'] == 'risk' ? JrcRelationship::RiskCase : JrcRelationship::SuccessPlan).where(assignment: assignment)
    return if rows.exists?(["metadata ->> 'playbook_source_key' = ?", key])
    return if step['kind'] == 'risk' && rows.exists?(source_key: "manual:#{key}")

    attrs = workflow_attributes(assignment, step, key, start)
    record = JrcRelationship::Workflow.new(@context).save(kind: step['kind'] == 'risk' ? 'risks' : 'plans', attributes: attrs)[:record]
    record.update!(metadata: record.metadata.merge('playbook_source_key' => key))
    @context.audit!(record, after: { source_key: key }, action: 'playbook_workflow_created')
  end

  def workflow_attributes(assignment, step, key, start)
    due_at = start + step['after_days'].days
    attrs = { assignment_id: assignment.id, request_id: key }
    if step['kind'] == 'risk'
      attrs.merge(reason: step['title'], kind: 'playbook', severity: 'high', due_at: step['after_days'].positive? ? due_at : nil)
    else
      milestones = [30, 60, 90].map do |days|
        { 'title' => "Acompanhamento #{days} dias", 'due_at' => (due_at + days.days).iso8601, 'status' => 'active' }
      end
      attrs.merge(title: step['title'], target_on: (due_at + 90.days).to_date, milestones: milestones)
    end
  end
end
