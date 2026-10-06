class JrcRelationship::CustomerSignals
  attr_reader :assignment, :context, :customer, :rules

  def initialize(assignment:, context:)
    @assignment, @context = assignment, context
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
        JrcCrm::Invoice.where(account_id: context.account.id, sales_order_id: customer.orders.select(:id)))
    invoices = invoices.where.not(status: %w[paid canceled]).where('due_on < ? AND balance_cents > 0', Date.current)
    invoices = invoices.none unless overview[:capabilities][:crm]
    invoices = JrcCrm::OrganizationalVisibility.new(account: context.account, user: context.user, relation: invoices).call unless context.policy.admin?
    csat = CsatSurveyResponse.where(account_id: context.account.id, conversation_id: customer.conversations.select(:id))
                            .where('created_at >= ?', 90.days.ago)
    nps = JrcRelationship::Survey.where(account_id: context.account.id, assignment_id: assignment.id, kind: 'nps')
                               .where.not(responded_at: nil).where('responded_at >= ?', 90.days.ago)
    nps_score = nps.average(:score)&.to_f
    ces = context.records(JrcRelationship::Survey).where(assignment: assignment, kind: 'ces', responded_at: 90.days.ago..Time.current)
    ces_score = ces.average(:score)&.to_f
    csat_score = csat.average(:rating)&.to_f
    tickets = customer.tickets.joins(:status).where(jrc_service_desk_ticket_statuses: { phase: %w[open waiting] })
    critical = tickets.joins(:priority).where(jrc_service_desk_priorities: { code: rules['critical_priority_codes'] }).count
    project_late = customer.projects.where(status: %w[planned active on_hold]).where('due_on < ?', Date.current).count
    late_tasks = customer.project_tasks.where.not(status: %w[completed canceled]).where('due_on < ?', Date.current).count
    plans = context.records(JrcRelationship::SuccessPlan).where(assignment: assignment)
    goals = plans.pluck(:goals).flatten(1)
    products = JrcCrm::OrderItem.where(sales_order_id: contracts.select(:sales_order_id)).where.not(product_id: nil).distinct.pluck(:product_id, :name)
    recent_tickets = customer.tickets.where(opened_at: 30.days.ago..Time.current)
    sentiment = JrcRelationship::SentimentMetric.call(Message.where(account_id: context.account.id, conversation_id: customer.conversations.select(:id),
      private: false, message_type: [0, 1], created_at: 90.days.ago..Time.current).where("sentiment IS NOT NULL AND sentiment <> '{}'::jsonb")
      .order(created_at: :desc, id: :desc).limit(100).pluck(:id, :sentiment))
    observations = {
      'sentiment' => sentiment.except(:source_ids),
      'adoption' => JrcRelationship::AdoptionMetric.call(goals: goals, metric: rules['adoption_metric']),
      'relationship' => observation(days, [100 - days * 100.0 / rules['no_contact_days'], 0].max, 'Customer360 last interaction / assignment date'),
      'service_desk' => observation({ critical: critical, breached: overview[:sla_breached] }, overview[:capabilities][:service_desk] ? [100 - critical * rules['ticket_penalty'] - overview[:sla_breached].to_i * rules['sla_penalty'], 0].max : nil, 'Authorized TicketPolicy and SlaClock'),
      'finance' => observation(invoices.sum(:balance_cents), overview[:capabilities][:crm] ? (invoices.exists? ? rules['overdue_finance_score'] : 100) : nil, 'Authorized customer invoices; positive overdue balance'),
      'satisfaction' => observation({ nps: nps_score, csat: csat_score, ces: ces_score }, nps_score ? nps_score * 10 :
        csat_score ? (csat_score - 1) * 25 : ces_score && ces_score * 10, 'Relational NPS/CES (0-10) and native conversation CSAT (1-5), last 90 days'),
      'contract' => observation(renewal_on, renewal_on ? [((renewal_on - Date.current).to_i * 100.0 / rules['renewal_days']).clamp(0, 100), 100].min : nil, 'Authorized active contract ends_on'),
      'projects' => observation({ delayed: project_late, delayed_tasks: late_tasks }, overview[:capabilities][:projects] ? [100 - project_late * rules['project_penalty'] - late_tasks * rules['task_penalty'], 0].max : nil, 'Authorized Projects/Tasks due_on'),
      'engagement' => observation(overview[:last_conversation_at], overview[:last_conversation_at] ? [100 - (Time.current - Time.iso8601(overview[:last_conversation_at])) / 1.day * 100 / rules['no_contact_days'], 0].max : nil, 'Authorized public conversation messages')
    }
    health = JrcRelationship::HealthScore.call(observations: observations, weights: context.configuration(assignment).effective_weights, rules: rules)
    product_health = products.to_h do |id, _name|
      product_observations = observations.merge('adoption' => JrcRelationship::AdoptionMetric.call(goals: goals, metric: rules['adoption_metric'], product_id: id))
      config = JrcRelationship::Configuration.find_by(account: context.account, scope_key: "product:#{id}") || context.configuration(assignment)
      [id, JrcRelationship::HealthScore.call(observations: product_observations, weights: config.effective_weights, rules: config.effective_rules)
        .merge(config_scope_key: config.scope_key, config_version: config.version)]
    end
    { segment_id: assignment.settings['segment_id'], product_id: assignment.settings['product_id'], business_unit_id: assignment.business_unit_id,
      health: health, product_health: product_health, products: products.map { |id, name| { id: id, name: name } }, portfolio_status: assignment.status,
      usage_growth: JrcRelationship::AdoptionMetric.growth(goals: goals, metric: rules['adoption_metric']),
      recurring_tickets: recent_tickets.count, recent_resolved_critical_ticket_ids: recent_tickets.joins(:status, :priority)
        .where(jrc_service_desk_ticket_statuses: { phase: %w[resolved closed] }, jrc_service_desk_priorities: { code: rules['critical_priority_codes'] }).pluck(:id),
      last_interaction_at: last, days_without_contact: days, renewal_on: renewal_on,
      mrr_cents: overview[:contracts_mrr_cents], csat: csat_score, ces: ces_score, nps_average: nps_score,
      nps: nps.exists? ? 100.0 * (nps.where('score >= 9').count - nps.where('score <= 6').count) / nps.count : nil,
      detractor: nps.where('score <= 6').exists?, critical_tickets: critical, sla_breached: overview[:sla_breached],
      overdue_cents: overview[:capabilities][:crm] ? invoices.sum(:balance_cents) : nil,
      delayed_projects: project_late + late_tasks, overdue_activities: customer.activities.overdue.count,
      active_contract_ids: contracts.pluck(:id), capabilities: overview[:capabilities],
      _source_ids: { contracts: contracts.pluck(:id), orders: customer.orders.pluck(:id), invoices: invoices.pluck(:id),
        tickets: customer.tickets.pluck(:id), projects: customer.projects.pluck(:id), project_tasks: customer.project_tasks.pluck(:id),
        conversations: customer.conversations.pluck(:id), activities: customer.activities.pluck(:id),
        csat: csat.pluck(:id), surveys: nps.pluck(:id) + ces.pluck(:id), calls: customer.calls&.pluck(:id) || [],
        ticket_events: customer.ticket_events.pluck(:id), project_events: customer.project_events.pluck(:id),
        plans: plans.pluck(:id),
        messages: [Message.where(account_id: context.account.id, conversation_id: customer.conversations.select(:id), private: false,
          message_type: [0, 1]).order(created_at: :desc, id: :desc).pick(:id)].compact + sentiment[:source_ids] } }
  end

  private

  def observation(raw, normalized, evidence)
    { raw: raw, normalized: normalized, evidence: evidence }
  end
end
