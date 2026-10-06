class JrcRelationship::OperationalRouting
  def initialize(context)
    @context = context
  end

  def prepare!(action, signals: {}, preserve_owner: false)
    signals ||= {}
    assignment = action.assignment
    queues = JrcOperations::Queue.active.where(account: @context.account)
      .order(Arel.sql("CASE WHEN code = 'RELATIONSHIP-GERAL' THEN 1 ELSE 0 END, id ASC"))
    queue = queues.detect { |row| queue_matches?(row, assignment, action, signals) }
    queue ||= JrcOperations::Queue.create_or_find_by!(account: @context.account, code: 'RELATIONSHIP-GERAL') do |row|
      row.name = 'Relacionamento'
      row.settings = { scopes: ['relationship'] }
    end
    queue.with_lock do
      policy = JrcOperations::SlaPolicy.active.where(account: @context.account, scope_kind: 'relationship')
        .where(operations_queue_id: [nil, queue.id]).order(Arel.sql('operations_queue_id DESC NULLS LAST, id ASC'))
        .where.not('conditions @> ?', { system_default: true }.to_json)
        .detect { |row| (row.request_kind.blank? || row.request_kind == action.kind) && matches?(row.conditions, assignment, action, signals) }
      policy ||= default_policy!(queue, action)
      action.operations_queue = queue
      action.operations_sla_policy = policy
      action.owner = resolve_owner(queue, assignment) unless preserve_owner
      Time.use_zone(Time.find_zone(@context.account.reporting_timezone) || Time.zone) { JrcOperations::SlaClock.new(action).start! }
      action.due_at ||= action.sla_due_at || action.first_action_due_at || action.stage_due_at
    end
    action
  end

  private

  def queue_matches?(queue, assignment, action, signals)
    return false unless queue.supports_scope?('relationship')
    return false if queue.business_unit_id && queue.business_unit_id != assignment.business_unit_id
    return false if queue.team_id && queue.team_id != assignment.team_id
    return false if queue.operating_company_id && queue.operating_company_id != assignment.business_unit&.company_id

    matches?(queue.settings, assignment, action, signals)
  end

  def matches?(config, assignment, action, signals)
    values = { 'business_unit_ids' => assignment.business_unit_id, 'segment_ids' => assignment.settings['segment_id'],
               'product_ids' => assignment.settings['product_id'], 'kinds' => action.kind, 'team_ids' => assignment.team_id }
    return false if values.any? { |key, value| Array(config[key]).any? && !Array(config[key]).map(&:to_s).include?(value.to_s) }
    mrr = signals[:mrr_cents]
    return false if config['min_mrr_cents'] && (mrr.nil? || mrr < config['min_mrr_cents'].to_i)
    return false if config['max_mrr_cents'] && (mrr.nil? || mrr > config['max_mrr_cents'].to_i)
    true
  end

  def default_policy!(queue, action)
    configuration = @context.configuration(action.assignment)
    rules = configuration.effective_rules
    first_minutes = (rules[action.kind == 'satisfaction' ? 'detractor_sla_hours' : 'sla_hours'] * 60).ceil
    total_minutes = (rules['sla_hours'] * 60).ceil
    JrcOperations::SlaPolicy.create_or_find_by!(account: @context.account, operations_queue: queue,
      scope_kind: 'relationship',
      name: "Relacionamento #{action.kind} — #{first_minutes}/#{total_minutes}m — #{configuration.scope_key} v#{configuration.version}",
      request_kind: action.kind) do |row|
      row.first_action_minutes = first_minutes
      row.total_minutes = total_minutes
      row.pause_statuses = JrcRelationship::Action::WAITING_STATUSES
      row.conditions = { system_default: true, config_scope: configuration.scope_key, config_version: configuration.version }
    end
  end

  def resolve_owner(queue, assignment)
    return assignment.owner if queue.assignment_strategy == 'manual' && assignment.owner
    allowed_ids = @context.assignable_users.pluck(:id)
    candidates = queue.candidate_users.where(id: allowed_ids).order(:id).select do |user|
      member = @context.account.account_users.find_by!(user_id: user.id)
      candidate = JrcRelationship::Context.new(member) if JrcRelationship::ModulePolicy.new({ account: @context.account, user: user, account_user: member }, @context.account).manage?
      candidate && candidate.assignments.exists?(id: assignment.id)
    end
    return assignment.owner if candidates.empty?
    ids = candidates.map(&:id)
    scope = JrcRelationship::Action.where(account: @context.account, operations_queue: queue, owner_id: ids)
    case queue.assignment_strategy
    when 'least_load'
      counts = scope.where(status: JrcRelationship::Action::ACTIVE_STATUSES).group(:owner_id).count
      candidates.min_by { |user| [counts.fetch(user.id, 0), user.id] }
    when 'round_robin'
      dates = scope.group(:owner_id).maximum(:created_at)
      candidates.min_by { |user| [dates[user.id] || Time.at(0), user.id] }
    when 'specialty'
      preferred = Array(queue.settings['specialty_user_ids']).map(&:to_i)
      candidates.find { |user| preferred.include?(user.id) } || candidates.first
    else
      configured = Array(queue.settings['user_ids']).map(&:to_i)
      candidates.find { |user| configured.include?(user.id) } || candidates.first
    end
  end
end
