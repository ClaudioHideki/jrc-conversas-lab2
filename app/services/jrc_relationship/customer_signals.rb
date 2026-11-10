class JrcRelationship::CustomerSignals
  SOURCE_MANIFEST = %i[contracts orders invoices tickets projects project_tasks conversations activities csat surveys calls
                       ticket_events project_events plans messages sla_clocks].freeze
  attr_reader :assignment, :context, :customer, :rules

  def initialize(assignment:, context:)
    @assignment = assignment
    @context = context
    @customer = assignment.customer_context(context.member)
    @rules = context.configuration(assignment).effective_rules
  end

  def call
    overview = customer.overview
    last = overview[:last_interaction_at] && Time.iso8601(overview[:last_interaction_at])
    days = ((Time.current - (last || assignment.created_at)) / 1.day).floor.clamp(0, 100_000)
    contracts = customer.contracts.where(status: %w[active expiring])
    renewal_on = contracts.minimum(:ends_on)
    invoices = JrcCrm::Invoice.where(account_id: context.account.id)
                              .where(contract_id: customer.contracts.select(:id)).or(
                                JrcCrm::Invoice.where(account_id: context.account.id, sales_order_id: customer.orders.select(:id))
                              )
    invoices = invoices.where.not(status: %w[paid canceled]).where('due_on < ? AND balance_cents > 0', Date.current)
    invoices = invoices.none unless overview[:capabilities][:crm]
    unless context.policy.admin?
      invoices = JrcCrm::OrganizationalVisibility.new(account: context.account, user: context.user,
                                                      relation: invoices).call
    end
    ratings = JrcRelationship::SatisfactionSignals.new(context, assignment, customer, rules).call
    @satisfaction_windows = { rules.fetch('satisfaction_window_days') => ratings }
    tickets = customer.tickets.joins(:status).where(jrc_service_desk_ticket_statuses: { phase: %w[open waiting] })
    critical = tickets.joins(:priority).where(jrc_service_desk_priorities: { code: rules['critical_priority_codes'] }).count
    project_late = customer.projects.where(status: %w[planned active on_hold]).where('due_on < ?', Date.current).count
    late_tasks = customer.project_tasks.where.not(status: %w[completed canceled]).where('due_on < ?', Date.current).count
    plans = context.records(JrcRelationship::SuccessPlan).where(assignment: assignment)
    goals = plans.pluck(:goals).flatten(1)
    products = JrcCrm::OrderItem.where(sales_order_id: contracts.select(:sales_order_id)).where.not(product_id: nil).distinct.pluck(:product_id,
                                                                                                                                    :name)
    products |= JrcCrm::ContractItem.where(contract_id: contracts.select(:id)).where.not(product_id: nil).distinct.pluck(:product_id, :name)
    recent_tickets = customer.tickets.where(opened_at: 30.days.ago..Time.current)
    sentiment = sentiment_observation
    observations = {
      'sentiment' => sentiment.except(:source_ids),
      'adoption' => JrcRelationship::AdoptionMetric.call(goals: goals, metric: rules['adoption_metric']),
      'relationship' => observation(days, [100 - days * 100.0 / rules['no_contact_days'], 0].max, 'Customer360 last interaction / assignment date'),
      'service_desk' => service_desk_observation(overview, critical),
      'finance' => observation(invoices.sum(:balance_cents), overview[:capabilities][:crm] ? (invoices.exists? ? rules['overdue_finance_score'] : 100) : nil, 'Authorized customer invoices; positive overdue balance'),
      'satisfaction' => satisfaction_observation(ratings),
      'contract' => observation(renewal_on, renewal_on ? [((renewal_on - Date.current).to_i * 100.0 / rules['renewal_days']).clamp(0, 100), 100].min : nil, 'Authorized active contract ends_on'),
      'projects' => observation({ delayed: project_late, delayed_tasks: late_tasks }, overview[:capabilities][:projects] ? [100 - project_late * rules['project_penalty'] - late_tasks * rules['task_penalty'], 0].max : nil, 'Authorized Projects/Tasks due_on'),
      'engagement' => observation(overview[:last_conversation_at], overview[:last_conversation_at] ? [100 - (Time.current - Time.iso8601(overview[:last_conversation_at])) / 1.day * 100 / rules['no_contact_days'], 0].max : nil, 'Authorized public conversation messages')
    }
    health = JrcRelationship::HealthScore.call(observations: observations, weights: context.configuration(assignment).effective_weights, rules: rules)
    product_history_sources = []
    product_health = products.to_h do |id, _name|
      config = JrcRelationship::Configuration.find_by(account: context.account, scope_key: "product:#{id}") || context.configuration(assignment)
      product_ratings = @satisfaction_windows[config.effective_rules.fetch('satisfaction_window_days')] ||=
        JrcRelationship::SatisfactionSignals.new(context, assignment, customer, config.effective_rules).call
      product_observations = observations.merge('adoption' => JrcRelationship::AdoptionMetric.call(goals: goals,
        metric: rules['adoption_metric'], product_id: id),
        'satisfaction' => satisfaction_observation(product_ratings))
      product_history_sources << product_ratings.fetch(:source_ids)
      measured = JrcRelationship::HealthScore.call(observations: product_observations, weights: config.effective_weights, rules: config.effective_rules)
                                            .merge(config_scope_key: config.scope_key, config_version: config.version)
      stable, sources = JrcRelationship::ProductHealthHysteresis.new(context: context, assignment: assignment, product_id: id,
                                                                    configuration: config).call(measured)
      product_history_sources << sources
      [id, stable]
    end
    manifest = source_ids(contracts: contracts, invoices: invoices, csat: ratings[:csat], nps: ratings[:nps], ces: ratings[:ces],
                          surveys: ratings[:surveys], window_days: ratings[:window_days], plans: plans, sentiment: sentiment)
    manifest = merge_health_sources(ratings.fetch(:source_ids), manifest)
    health, history_sources = JrcRelationship::HealthHysteresis.new(context: context, assignment: assignment).call(health)
    manifest = product_history_sources.reduce(manifest) { |current, sources| merge_health_sources(sources, current) }
    { segment_id: assignment.settings['segment_id'], product_id: assignment.settings['product_id'], business_unit_id: assignment.business_unit_id,
      health: health, product_health: product_health, products: products.map { |id, name| { id: id, name: name } },
      portfolio_status: assignment.status,
      usage_growth: JrcRelationship::AdoptionMetric.growth(goals: goals, metric: rules['adoption_metric']),
      recurring_tickets: recent_tickets.count, recent_resolved_critical_ticket_ids: resolved_critical_ids(recent_tickets),
      last_interaction_at: last, days_without_contact: days, renewal_on: renewal_on,
      mrr_cents: overview[:contracts_mrr_cents], csat: ratings[:csat_score], ces: ratings[:ces_score], nps_average: ratings[:nps_score],
      nps: nps_score(ratings[:nps]),
      detractor: ratings[:nps].where('score <= 6').exists?, critical_tickets: critical, sla_breached: overview[:sla_breached],
      unmanaged_satisfaction: ratings[:unmanaged],
      overdue_cents: overview[:capabilities][:crm] ? invoices.sum(:balance_cents) : nil,
      delayed_projects: project_late + late_tasks,
      overdue_activities: customer.activities.overdue.where("NOT (COALESCE(jrc_crm_activities.metadata, '{}'::jsonb) ? 'relationship_action_id')").count,
      active_contract_ids: contracts.pluck(:id), capabilities: overview[:capabilities],
      _source_ids: merge_health_sources(history_sources, manifest) }
  end

  private

  def merge_health_sources(history, current)
    return current if history.empty?

    SOURCE_MANIFEST.to_h { |key| [key, (Array(current[key]) + Array(history[key.to_s])).uniq] }
  end

  def sentiment_observation
    JrcRelationship::SentimentSignals.new(context: context, customer: customer, window_days: rules.fetch('sentiment_window_days')).call
  end

  def resolved_critical_ids(tickets)
    tickets.joins(:status, :priority).where(
      jrc_service_desk_ticket_statuses: { phase: %w[resolved closed] },
      jrc_service_desk_priorities: { code: rules['critical_priority_codes'] }
    ).pluck(:id)
  end

  def nps_score(surveys)
    return unless surveys.exists?

    100.0 * (surveys.where('score >= 9').count - surveys.where('score <= 6').count) / surveys.count
  end

  def satisfaction_observation(ratings)
    raw = { nps: ratings[:nps_score], csat: ratings[:csat_score], ces: ratings[:ces_score] }
    observation(raw, normalized_satisfaction(raw, ratings[:ces_normalized]),
                "Authorized relational NPS/CES and native/shared CSAT, last #{ratings.fetch(:window_days)} days")
      .merge(measurement: ratings.fetch(:evidence))
  end

  def normalized_satisfaction(raw, ces_normalized)
    return raw[:nps] * 10 if raw[:nps]
    return (raw[:csat] - 1) * 25 if raw[:csat]

    ces_normalized
  end

  def source_ids(data)
    SOURCE_MANIFEST.index_with { |key| source_ids_for(key, data) }
  end

  def source_ids_for(key, data)
    case key
    when :surveys
      csat = data[:surveys].where(kind: 'csat', responded_at: data.fetch(:window_days).days.ago..Time.current).pluck(:id)
      data[:nps].pluck(:id) + data[:ces].pluck(:id) + csat
    when :messages then recent_message_ids + data[:sentiment][:source_ids]
    when :calls then customer.calls&.pluck(:id) || []
    else (data[key] || customer.public_send(key)).pluck(:id)
    end
  end

  def recent_message_ids
    [Message.where(account_id: context.account.id, conversation_id: customer.conversations.select(:id), private: false,
                   message_type: [0, 1]).order(created_at: :desc, id: :desc).pick(:id)].compact
  end

  def observation(raw, normalized, evidence)
    { raw: raw, normalized: normalized, evidence: evidence }
  end

  def service_desk_observation(overview, critical)
    breached = overview[:sla_breached]
    normalized = [100 - critical * rules['ticket_penalty'] - breached * rules['sla_penalty'], 0].max if overview[:capabilities][:service_desk_sla]
    observation({ critical: critical, breached: breached }, normalized,
                'Authorized customer/SLA TicketPolicy intersection and native calendar ClockProjection; missing SLA access is unavailable')
  end
end
