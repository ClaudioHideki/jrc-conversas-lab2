require 'digest'

class JrcRelationship::Processor
  def initialize(context:, assignment:)
    @context, @assignment = context, assignment
  end

  def call
    @assignment.with_lock do
      data = JrcRelationship::CustomerSignals.new(assignment: @assignment, context: @context).call
      reconcile_renewals!
      configuration = @context.configuration(@assignment)
      fingerprint = Digest::SHA256.hexdigest([Date.current, configuration.scope_key, configuration.version, configuration.effective_weights,
        configuration.effective_rules, @context.access_signature, data.to_json].join(':'))
      previous = JrcRelationship::HealthSnapshot.where(assignment: @assignment, viewer: @context.user,
        config_scope_key: configuration.scope_key, config_version: configuration.version, access_signature: @context.access_signature)
        .where.not(fingerprint: fingerprint)
      previous = JrcRelationship::SnapshotAccess.scope(@context, previous).order(:id).last
      if previous&.score && data.dig(:health, :score)
        data[:health_change] = { previous: previous.score.to_f, current: data[:health][:score],
                                drop: (previous.score.to_f - data[:health][:score]).round(2), snapshot_id: previous.id }
        previous.signals.fetch('_source_ids', {}).each do |key, ids|
          data[:_source_ids][key.to_sym] = (Array(data[:_source_ids][key.to_sym]) + ids).uniq
        end
      end
      snapshot = JrcRelationship::HealthSnapshot.find_or_initialize_by(assignment: @assignment, viewer: @context.user, fingerprint: fingerprint)
      if snapshot.new_record?
        snapshot.assign_attributes(account: @context.account, config_version: configuration.version, config_scope_key: configuration.scope_key, score: data[:health][:score],
                                   band: data[:health][:band], factors: data[:health][:factors], signals: data,
                                   access_signature: @context.access_signature, calculated_at: Time.current)
        snapshot.save!
        @context.audit!(snapshot, after: { score: snapshot.score, band: snapshot.band }, action: 'health_calculated')
      end
      evaluate(data, configuration.effective_rules)
      data
    end
  end

  def action!(kind, reason, data, rules, key: kind)
    active = @assignment.actions.where(kind: kind, status: JrcRelationship::Action::ACTIVE_STATUSES)
    keyed = %w[renewal post_ticket expansion].include?(kind)
    active = active.where(source_key: key) if keyed
    current = active.first
    priority = JrcRelationship::Priority.call(data: data, rules: rules, kind: kind, today: Date.current)
    if current
      if current.priority != priority[:score] || current.factors != priority[:factors].deep_stringify_keys
        before = current.attributes.slice('priority', 'factors')
        current.update!(priority: priority[:score], factors: priority[:factors], metadata: current.metadata.merge('_source_ids' => data[:_source_ids]))
        @context.audit!(current, before: before, after: current.attributes.slice('priority', 'factors'), action: 'priority_updated')
      end
      return current
    end
    key = "#{key}:#{Date.current}" unless keyed
    record = JrcRelationship::Action.find_or_initialize_by(assignment: @assignment, source_key: key)
    return record if record.persisted?
    record.assign_attributes(account: @context.account, owner: @assignment.owner, kind: kind, reason: reason,
                             priority: priority[:score], factors: priority[:factors],
                             due_at: Time.current + rules['sla_hours'].hours, metadata: { _source_ids: data[:_source_ids] })
    JrcRelationship::OperationalRouting.new(@context).prepare!(record, signals: data)
    record.save!
    JrcRelationship::Workflow.new(@context).project_action!(record)
    @context.audit!(record, after: record.attributes.slice('kind', 'priority', 'due_at'), action: 'action_created')
    record
  end

  private

  def reconcile_renewals!
    customer = @assignment.customer_context(@context.member)
    @context.records(JrcRelationship::Renewal).where(assignment: @assignment, status: %w[open negotiating]).find_each do |row|
      signed = customer.contracts.where(source_contract_id: row.contract_id, signature_status: 'signed').order(:id).last
      lost = row.deal_id && customer.deals.where(id: row.deal_id, status: 'lost').exists?
      next unless signed || lost
      row.with_lock do
        before = { status: row.status }
        row.update!(status: signed ? 'won' : 'lost', metadata: row.metadata.merge(
          'renewed_contract_id' => signed&.id, 'renewal_order_id' => signed&.sales_order_id, 'reconciled_at' => Time.current.iso8601))
        @context.audit!(row, before: before, after: { status: row.status }, action: 'renewal_commercial_result')
      end
    end
  end

  def evaluate(data, rules)
    score = data.dig(:health, :score)
    if data.dig(:health_change, :drop).to_f >= rules['health_drop_points']
      action = action!('health_drop', 'Queda do Health Score acima do limite configurado', data, rules)
      JrcRelationship::Playbooks.new(@context).run!(@assignment, 'health', source_key: action.id)
    end
    if score && score < rules['risk_threshold']
      action = action!('health', 'Health Score abaixo do limite configurado', data, rules)
      risk!('health', 'Health Score abaixo do limite configurado', score < rules['critical_threshold'] ? 'critical' : 'high', data)
      JrcRelationship::Playbooks.new(@context).run!(@assignment, 'health', source_key: action.id)
    end
    if data[:days_without_contact] >= rules['no_contact_days']
      action = action!('no_contact', 'Cliente sem contato na cadência configurada', data, rules)
      JrcRelationship::Playbooks.new(@context).run!(@assignment, 'no_contact', source_key: action.id)
    end
    if data[:detractor] || (data[:csat] && data[:csat] < rules['csat_threshold']) || (data[:ces] && data[:ces] < rules['ces_threshold'])
      action = action!('satisfaction', 'Detrator NPS / CSAT / CES baixo', data, rules)
      risk!('satisfaction', 'Recuperar experiência do cliente', 'high', data)
      JrcRelationship::Playbooks.new(@context).run!(@assignment, 'satisfaction', source_key: action.id)
    end
    if data[:critical_tickets].positive? || data[:sla_breached].to_i.positive?
      action = action!('ticket', 'Chamados críticos ou SLA vencido', data, rules)
      JrcRelationship::Playbooks.new(@context).run!(@assignment, 'ticket', source_key: action.id)
    end
    action!('finance', 'Saldo financeiro vencido', data, rules) if data[:overdue_cents].to_i.positive?
    action!('recurring_ticket', 'Reincidência de chamados no período', data, rules) if data[:recurring_tickets].to_i >= rules['recurring_ticket_count']
    Array(data[:recent_resolved_critical_ticket_ids]).each do |ticket_id|
      action = action!('post_ticket', 'Follow-up de satisfação após chamado crítico resolvido', data, rules, key: "post-ticket:#{ticket_id}")
      JrcRelationship::Playbooks.new(@context).run!(@assignment, 'ticket', source_key: action.id)
    end
    expansion = expansion!(data, rules)
    JrcRelationship::Playbooks.new(@context).run!(@assignment, 'expansion', source_key: expansion.id) if expansion
    action!('onboarding', 'Projeto ou tarefa em atraso', data, rules) if data[:delayed_projects].positive?
    action!('activity', 'Atividade vencida', data, rules) if data[:overdue_activities].positive?
    @assignment.customer_context(@context.member).contracts.where(id: data[:active_contract_ids])
      .where(ends_on: Date.current..(Date.current + rules['renewal_days'].days)).find_each do |contract|
      renewal = JrcRelationship::Renewal.find_or_initialize_by(contract: contract, renewal_on: contract.ends_on)
      if renewal.new_record?
        renewal.assign_attributes(account: @context.account, assignment: @assignment, owner: @assignment.owner)
        renewal.save!
        @context.audit!(renewal, action: 'renewal_opened')
      end
      action!('renewal', "Renovação #{contract.contract_number}", data, rules, key: "renewal:#{contract.id}:#{contract.ends_on}")
      JrcRelationship::Playbooks.new(@context).run!(@assignment, 'renewal', source_key: renewal.id)
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
      metadata: { _source_ids: data[:_source_ids] }, due_at: @context.configuration(@assignment).effective_rules['sla_hours'].hours.from_now)
    risk.save!
    @context.audit!(risk, action: 'risk_detected')
    action = @assignment.actions.where(kind: kind, status: JrcRelationship::Action::ACTIVE_STATUSES).first
    action.update!(metadata: action.metadata.merge('relationship_risk_id' => risk.id)) if action
    risk
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
    products = Array(data[:products]).map { |product| product[:id] }
    suggested = @context.account.jrc_crm_products.active.where.not(id: products).order(:id).first
    row = JrcRelationship::ExpansionSignal.create!(account: @context.account, assignment: @assignment, owner: @assignment.owner,
      title: revenue_growth ? 'Expansão: crescimento observado da receita recorrente' : 'Expansão: crescimento observado de uso', product: suggested, potential_cents: 0,
      evidence: "#{revenue_growth ? "MRR observado: #{base} → #{data[:mrr_cents]} centavos." : "Uso observado: #{usage[:baseline]} → #{usage[:current]}; #{usage[:evidence]}"} Potencial ainda depende de qualificação comercial.",
      metadata: { source_key: key, automatic: true, kind: suggested ? 'cross_sell' : 'upsell', _source_ids: data[:_source_ids] })
    action!('expansion', 'Qualificar oportunidade de expansão', data, rules, key: "expansion:#{row.id}")
    @context.audit!(row, action: 'expansion_detected')
    row
  end
end
