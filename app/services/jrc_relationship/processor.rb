require 'digest'

class JrcRelationship::Processor
  def initialize(context:, assignment:)
    @context = context
    @assignment = assignment
  end

  def call
    @assignment.with_lock do
      data = JrcRelationship::CustomerSignals.new(assignment: @assignment, context: @context).call
      reconcile_commercial! if @context.policy.manage?
      configuration = @context.configuration(@assignment)
      record_health_trend!(data, configuration)
      # Keep lineage in stored evidence without treating each refresh as a new observation.
      fingerprint_data = data.deep_dup
      fingerprint_data.except!(:health_trend)
      [fingerprint_data[:health], *fingerprint_data.fetch(:product_health, {}).values].each do |health|
        health&.dig(:hysteresis)&.except!(:previous_snapshot_id, :previous_band)
      end
      fingerprint = Digest::SHA256.hexdigest([Date.current, configuration.scope_key, configuration.version, configuration.effective_weights,
                                              configuration.effective_rules, @context.access_signature, fingerprint_data.to_json].join(':'))
      previous = JrcRelationship::HealthSnapshot.where(assignment: @assignment, viewer: @context.user,
                                                       config_scope_key: configuration.scope_key, config_version: configuration.version,
                                                       access_signature: @context.access_signature)
                                                .where.not(fingerprint: fingerprint)
      previous = JrcRelationship::SnapshotAccess.scope(@context, previous).order(:id).last
      record_health_change!(data, previous)
      snapshot = JrcRelationship::HealthSnapshot.find_or_initialize_by(assignment: @assignment, viewer: @context.user, fingerprint: fingerprint)
      if snapshot.new_record?
        snapshot.assign_attributes(account: @context.account, config_version: configuration.version, config_scope_key: configuration.scope_key,
                                   score: data[:health][:score],
                                   band: data[:health][:band], factors: data[:health][:factors], signals: data,
                                   access_signature: @context.access_signature, calculated_at: Time.current)
        snapshot.save!
        @context.audit!(snapshot, after: { score: snapshot.score, band: snapshot.band }, action: 'health_calculated')
      end
      evaluate(data, configuration.effective_rules) if @context.policy.manage?
      data
    end
  end

  def action!(kind, reason, data, rules, key: kind)
    health_family = %w[health health_drop].include?(kind)
    active = @assignment.actions.where(kind: health_family ? %w[health health_drop] : kind, status: JrcRelationship::Action::ACTIVE_STATUSES)
    key = 'health' if health_family
    keyed = %w[renewal post_ticket expansion].include?(kind)
    active = active.where(source_key: key) if keyed
    current = active.first
    manual = current&.metadata&.dig('manual_priority') == true ? current.priority : nil
    related = health_family ? (Array(current&.metadata&.dig('related_signals')) + [kind]).uniq : []
    priority_kind = related.include?('health_drop') ? 'health_drop' : kind
    priority = JrcRelationship::Priority.call(data: data, rules: rules, kind: priority_kind, today: Date.current, manual_priority: manual)
    cause_digest = JrcRelationship::AutomaticActionCooldown.digest(kind: kind, key: key, data: data)
    if current
      if current.priority != priority[:score] || current.factors != priority[:factors].deep_stringify_keys ||
         (health_family && current.metadata['related_signals'] != related) ||
         (current.metadata['automatic'] && current.metadata['automatic_cause_digest'] != cause_digest)
        before = current.attributes.slice('priority', 'factors')
        metadata = current.metadata.merge('_source_ids' => data[:_source_ids])
        metadata['related_signals'] = related if health_family
        metadata['automatic_cause_digest'] = cause_digest if current.metadata['automatic']
        current.update!(priority: priority[:score], factors: priority[:factors], metadata: metadata)
        @context.audit!(current, before: before, after: current.attributes.slice('priority', 'factors'), action: 'priority_updated')
      end
      return current
    end
    cooldown = JrcRelationship::AutomaticActionCooldown.new(context: @context, assignment: @assignment, digest: cause_digest,
      hours: rules.fetch('automatic_action_cooldown_hours', 0))
    return unless cooldown.allow?

    key = "#{key}:#{Date.current}" unless keyed
    record = JrcRelationship::Action.find_or_initialize_by(assignment: @assignment, source_key: key)
    return record if record.persisted?
    record.assign_attributes(account: @context.account, owner: @assignment.owner, kind: kind, reason: reason,
                             priority: priority[:score], factors: priority[:factors],
                             due_at: Time.current + rules['sla_hours'].hours,
                             metadata: { _source_ids: data[:_source_ids], automatic: true, automatic_cause_digest: cause_digest }
                               .merge(health_family ? { related_signals: related } : {}))
    JrcRelationship::OperationalRouting.new(@context).prepare!(record, signals: data)
    persist_automatic_action!(record)
  end

  private

  def persist_automatic_action!(record)
    JrcRelationship::AutomaticActionBudget.new(context: @context, assignment: @assignment).call do
      record.save!
      JrcRelationship::Workflow.new(@context).project_action!(record)
      @context.audit!(record, after: record.attributes.slice('kind', 'priority', 'due_at'), action: 'action_created')
      record
    end
  end

  def record_health_trend!(data, configuration)
    result = JrcRelationship::HealthTrend.new(context: @context, assignment: @assignment, configuration: configuration).call(data.fetch(:health))
    data[:health_trend] = result.fetch(:trend)
    result.fetch(:source_ids).each do |key, ids|
      data[:_source_ids][key.to_sym] = (Array(data[:_source_ids][key.to_sym]) + ids).uniq
    end
  end

  def record_health_change!(data, previous)
    return unless previous&.score && data.dig(:health, :score)

    previous_score = previous.score.to_f
    data[:health_change] = { previous: previous_score, current: data[:health][:score],
                             drop: (previous_score - data[:health][:score]).round(2), snapshot_id: previous.id }
    previous.signals.fetch('_source_ids', {}).each do |key, ids|
      data[:_source_ids][key.to_sym] = (Array(data[:_source_ids][key.to_sym]) + ids).uniq
    end
  end

  def reconcile_commercial!
    reconcile_renewals!
    JrcRelationship::CommercialReturn.new(@context, @assignment).call
  end

  def reconcile_renewals!
    JrcRelationship::RenewalReconciliation.new(@context, @assignment).call
  end

  def evaluate(data, rules)
    score = data.dig(:health, :score)
    if data.dig(:health_change, :drop).to_f >= rules['health_drop_points']
      action = action!('health_drop', 'Queda do Health Score acima do limite configurado', data, rules)
      JrcRelationship::Playbooks.new(@context).run!(@assignment, 'health', source_key: action.id) if action
    end
    if score && data.dig(:health, :band).in?(%w[risk critical])
      reason = if data.dig(:health, :hysteresis, :retained)
                 'Faixa de risco mantida até confirmar a margem de recuperação'
               else
                 'Health Score abaixo do limite configurado'
               end
      action = action!('health', reason, data, rules)
      risk!('health', reason, data.dig(:health, :band) == 'critical' ? 'critical' : 'high', data)
      JrcRelationship::Playbooks.new(@context).run!(@assignment, 'health', source_key: action.id) if action
    end
    if data[:days_without_contact] >= rules['no_contact_days']
      action = action!('no_contact', 'Cliente sem contato na cadência configurada', data, rules)
      JrcRelationship::Playbooks.new(@context).run!(@assignment, 'no_contact', source_key: action.id) if action
    end
    if data[:unmanaged_satisfaction]
      action = action!('satisfaction', 'Detrator NPS / CSAT / CES baixo', data, rules)
      risk!('satisfaction', 'Recuperar experiência do cliente', 'high', data)
      JrcRelationship::Playbooks.new(@context).run!(@assignment, 'satisfaction', source_key: action.id) if action
    end
    if data[:critical_tickets].positive? || data[:sla_breached].to_i.positive?
      action = action!('ticket', 'Chamados críticos ou SLA vencido', data, rules)
      JrcRelationship::Playbooks.new(@context).run!(@assignment, 'ticket', source_key: action.id) if action
    end
    action!('finance', 'Saldo financeiro vencido', data, rules) if data[:overdue_cents].to_i.positive?
    action!('recurring_ticket', 'Reincidência de chamados no período', data, rules) if data[:recurring_tickets].to_i >= rules['recurring_ticket_count']
    Array(data[:recent_resolved_critical_ticket_ids]).each do |ticket_id|
      action = action!('post_ticket', 'Follow-up de satisfação após chamado crítico resolvido', data, rules, key: "post-ticket:#{ticket_id}")
      JrcRelationship::Playbooks.new(@context).run!(@assignment, 'ticket', source_key: action.id) if action
    end
    expansion = expansion!(data, rules)
    JrcRelationship::Playbooks.new(@context).run!(@assignment, 'expansion', source_key: expansion.id) if expansion
    action!('onboarding', 'Projeto ou tarefa em atraso', data, rules) if data[:delayed_projects].positive?
    action!('activity', 'Atividade vencida', data, rules) if data[:overdue_activities].positive?
    @assignment.customer_context(@context.member).contracts.where(id: data[:active_contract_ids])
               .where(ends_on: Date.current..(Date.current + JrcRelationship::RenewalWindow.horizon(rules).days)).find_each do |contract|
      renewal = JrcRelationship::Renewal.find_or_initialize_by(contract: contract, renewal_on: contract.ends_on)
      if renewal.new_record?
        renewal.assign_attributes(account: @context.account, assignment: @assignment, owner: @assignment.owner)
        renewal.save!
        @context.audit!(renewal, action: 'renewal_opened')
      end
      action = action!('renewal', "Renovação #{contract.contract_number}", data, rules, key: "renewal:#{contract.id}:#{contract.ends_on}")
      JrcRelationship::Playbooks.new(@context).run!(@assignment, 'renewal', source_key: renewal.id) if action
    end
  end

  def risk!(kind, reason, severity, data)
    active = JrcRelationship::RiskCase.where(assignment: @assignment, kind: kind, status: %w[detected analyzing planned negotiating]).first
    if active
      if active.severity != severity
        before = { severity: active.severity }
        active.update!(severity: severity, metadata: active.metadata.merge('_source_ids' => data[:_source_ids]))
        @context.audit!(active, before: before, after: { severity: severity }, action: 'risk_reclassified')
      end
      return active
    end
    risk = JrcRelationship::RiskCase.find_or_initialize_by(assignment: @assignment, source_key: "#{kind}:#{Date.current}")
    return if risk.persisted?

    risk.assign_attributes(account: @context.account, owner: @assignment.owner, kind: kind, reason: reason, severity: severity,
                           metadata: { _source_ids: data[:_source_ids] },
                           due_at: @context.configuration(@assignment).effective_rules['sla_hours'].hours.from_now)
    persist_risk!(risk)
    action = @assignment.actions.where(kind: kind, status: JrcRelationship::Action::ACTIVE_STATUSES).first
    action.update!(metadata: action.metadata.merge('relationship_risk_id' => risk.id)) if action
    risk
  end

  def persist_risk!(risk)
    JrcRelationship::RiskFinancialSnapshot.capture!(risk, @context)
    risk.save!
    @context.audit!(risk, action: 'risk_detected')
  end

  def expansion!(data, rules)
    return unless data[:mrr_cents].to_i.positive? && data.dig(:health, :score).to_f >= rules['healthy_threshold']

    history = JrcRelationship::HealthSnapshot.where(assignment: @assignment, viewer: @context.user, access_signature: @context.access_signature)
                                             .where('calculated_at < ?', 30.days.ago)
    previous = JrcRelationship::SnapshotAccess.scope(@context, history).order(:calculated_at).last
    base = previous&.signals&.dig('mrr_cents').to_i
    revenue_growth = base.positive? && 100.0 * (data[:mrr_cents] - base) / base >= rules['growth_threshold_percent']
    usage = data[:usage_growth]
    usage_growth = usage && usage[:percent] >= rules['growth_threshold_percent']
    return unless revenue_growth || usage_growth

    key = revenue_growth ? "growth:#{previous.id}" : "usage:#{usage[:product_id]}:#{usage[:baseline]}:#{usage[:current]}"
    signals = JrcRelationship::ExpansionSignal.where(assignment: @assignment)
    row = signals.where(status: %w[suggested approved converted]).where("metadata ->> 'automatic' = 'true'").order(:id).first ||
          signals.where("metadata ->> 'source_key' = ?", key).first
    return row if row

    attributes = JrcRelationship::ExpansionAttributes.new(@context, @assignment).call(
      data: data, key: key, revenue_growth: revenue_growth, usage_growth: usage_growth, base: base
    )
    row = JrcRelationship::ExpansionSignal.create!(attributes)
    action!('expansion', 'Qualificar oportunidade de expansão', data, rules, key: "expansion:#{row.id}")
    @context.audit!(row, action: 'expansion_detected')
    row
  end
end
