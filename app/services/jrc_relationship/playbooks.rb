class JrcRelationship::Playbooks
  def initialize(context)
    @context = context
  end

  def run!(assignment, trigger, source_key: 'handoff', playbook_id: nil)
    rows = JrcRelationship::Playbook.where(account: @context.account, active: true, trigger_kind: trigger).to_a
    rows = rows.select { |row| row.id == playbook_id.to_i } if playbook_id
    if rows.any? { |row| row.conditions.present? }
      signals = JrcRelationship::CustomerSignals.new(assignment: assignment, context: @context).call
      rows = rows.select { |row| JrcRelationship::PlaybookConditions.match?(row.conditions, signals) }
    end
    steps = rows.flat_map { |row| row.steps.map.with_index { |step, index| ["playbook:#{row.id}:#{index}", step] } }
    if trigger == 'onboarded' && steps.empty? && !playbook_id && !JrcRelationship::Playbook.where(account: @context.account, active: true, trigger_kind: trigger).exists?
      steps = [30, 60, 90].map { |days| ["onboarded:#{days}", { 'kind' => 'activity', 'title' => "Acompanhamento pós-go-live #{days} dias", 'after_days' => days }] }
    end
    steps.each do |key, step|
      key = "#{key}:#{source_key}"
      start = trigger == 'onboarded' ? assignment.created_at : Time.current.beginning_of_day
      if step['kind'] == 'activity'
        next unless JrcOperations::Access.crm?(@context.member)
        JrcRelationship::Workflow.new(@context).activity!(assignment: assignment, title: step['title'],
          due_at: start + step['after_days'].to_i.days, request_id: key)
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
end
