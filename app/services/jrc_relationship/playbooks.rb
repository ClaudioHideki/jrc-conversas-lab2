class JrcRelationship::Playbooks
  def initialize(context)
    @context = context
  end

  def run!(assignment, trigger, source_key: 'handoff', playbook_id: nil)
    @context.assignment(assignment.id, write: true)
    assignment.with_lock { execute!(assignment, trigger, source_key: source_key, playbook_id: playbook_id) }
  end

  private

  def execute!(assignment, trigger, source_key:, playbook_id:)
    rows = JrcRelationship::Playbook.where(account: @context.account, active: true, trigger_kind: trigger).to_a
    rows = rows.select { |row| row.id == playbook_id.to_i } if playbook_id
    if rows.any? { |row| row.conditions.present? }
      signals = JrcRelationship::CustomerSignals.new(assignment: assignment, context: @context).call
      rows = rows.select { |row| JrcRelationship::PlaybookConditions.match?(row.conditions, signals) }
    end
    steps = rows.flat_map { |row| row.steps.map.with_index { |step, index| ["playbook:#{row.id}:#{step['step_key'].presence || index}", step] } }
    if trigger == 'onboarded' && steps.empty? && !playbook_id && !JrcRelationship::Playbook.where(account: @context.account, active: true, trigger_kind: trigger).exists?
      steps = JrcRelationship::PlaybookSteps.onboarding.map do |step|
        key = step['kind'] == 'activity' ? "onboarded:#{step['after_days']}" : "onboarded:#{step['kind']}"
        [key, step]
      end
    end
    steps.each do |key, step|
      key = "#{key}:#{source_key}"
      start = trigger == 'onboarded' ? assignment.created_at : Time.current.beginning_of_day
      if %w[activity meeting].include?(step['kind'])
        next unless JrcOperations::Access.crm?(@context.member)
        JrcRelationship::Workflow.new(@context).activity!(assignment: assignment, title: step['title'],
          due_at: start + step['after_days'].to_i.days, kind: step['kind'] == 'meeting' ? 'meeting' : 'task', request_id: key)
      elsif %w[success_plan risk].include?(step['kind'])
        workflow_step!(assignment, step, key, start)
      else
        record = assignment.actions.find_or_initialize_by(source_key: key)
        next if record.persisted?
        record.assign_attributes(account: @context.account, owner: assignment.owner, reason: step['title'], kind: trigger,
          due_at: start + step['after_days'].to_i.days)
        JrcRelationship::OperationalRouting.new(@context).prepare!(record)
        record.save!
        JrcRelationship::Workflow.new(@context).project_action!(record)
        @context.audit!(record, action: 'playbook_action')
      end
    end
  end

  def workflow_step!(assignment, step, key, start)
    due_at = start + step['after_days'].days
    model = step['kind'] == 'risk' ? JrcRelationship::RiskCase : JrcRelationship::SuccessPlan
    rows = @context.records(model).where(assignment: assignment)
    return if rows.where("metadata ->> 'playbook_source_key' = ?", key).exists?
    # Also recognize a legacy/manual source key if a retry follows an interruption.
    return if step['kind'] == 'risk' && rows.where(source_key: "manual:#{key}").exists?
    attrs = { assignment_id: assignment.id, request_id: key }
    if step['kind'] == 'risk'
      attrs.merge!(reason: step['title'], kind: 'playbook', severity: 'high', due_at: step['after_days'].positive? ? due_at : nil)
    else
      milestones = [30, 60, 90].map do |days|
        { 'title' => "Acompanhamento #{days} dias", 'due_at' => (due_at + days.days).iso8601, 'status' => 'active' }
      end
      attrs.merge!(title: step['title'], target_on: (due_at + 90.days).to_date, milestones: milestones)
    end
    record = JrcRelationship::Workflow.new(@context).save(kind: step['kind'] == 'risk' ? 'risks' : 'plans', attributes: attrs)[:record]
    record.update!(metadata: record.metadata.merge('playbook_source_key' => key))
    @context.audit!(record, after: { source_key: key }, action: 'playbook_workflow_created')
  end
end
