class JrcRelationship::PlaybookPreview
  def initialize(context)
    @context = context
  end

  def call(assignment:, playbook:, source_key:)
    @context.assignment(assignment.id, write: true)
    raise ActiveRecord::RecordInvalid, playbook unless playbook.valid?
    raise Pundit::NotAuthorizedError unless playbook.account_id == @context.account.id
    raise ArgumentError, 'Invalid playbook source key' unless source_key.to_s.length.between?(1, 180)

    signals = JrcRelationship::CustomerSignals.new(assignment: assignment, context: @context).call
    matched = JrcRelationship::PlaybookConditions.match?(playbook.conditions, signals)
    handoff_blocked = handoff_blocked?(assignment, playbook)
    state = !matched || handoff_blocked ? 'blocked' : 'preview'
    { state: state, matched: matched, active: playbook.active, version: playbook.version,
      reason: preview_reason(handoff_blocked, matched),
      steps: preview_steps(assignment, playbook, source_key, state) }
  end

  private

  def handoff_blocked?(assignment, playbook)
    playbook.trigger_kind == 'onboarded' && @context.configuration(assignment).effective_rules['handoff_acceptance_required'] &&
      !JrcRelationship::HandoffCase.exists?(account: @context.account, assignment: assignment,
                                            source_type: 'JrcCrm::SalesOrder', status: 'accepted')
  end

  def preview_reason(handoff_blocked, matched)
    return 'handoff_acceptance_required' if handoff_blocked

    'conditions_not_matched' unless matched
  end

  def preview_steps(assignment, playbook, source_key, state)
    request = { assignment: assignment, playbook: playbook, source_key: source_key, state: state }
    playbook.steps.map.with_index { |step, index| preview_step(request, step, index) }
  end

  def preview_step(request, step, index)
    book = request[:playbook]
    key = step_key(book, step, index, request[:source_key])
    return { step_key: key, kind: step['kind'], state: 'blocked', reason: 'playbook_not_eligible' } if request[:state] == 'blocked'

    return flow_preview(request, step, key) if step['kind'] == 'flow'

    permitted = %w[activity meeting].exclude?(step['kind']) || JrcOperations::Access.crm?(@context.member)
    { step_key: key, kind: step['kind'], state: permitted ? 'planned' : 'blocked',
      reason: permitted ? nil : 'native_permission_unavailable', after_days: step['after_days'] }
  end

  def step_key(book, step, index, source_key)
    "playbook:#{book.id || 'draft'}:v#{book.version}:#{step['step_key'].presence || index}:#{source_key}"
  end

  def flow_preview(request, step, key)
    result = JrcRelationship::PlaybookFlow.new(@context).preview(assignment: request[:assignment], step: step,
                                                                 source_key: key, playbook: request[:playbook])
    result.merge(step_key: key, kind: 'flow')
  end
end
