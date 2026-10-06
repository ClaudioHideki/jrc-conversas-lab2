class JrcRelationship::WorkContext
  def initialize(context:, assignment:, period: nil)
    @context, @assignment = context, context.assignment(assignment.id)
    @period = period || (90.days.ago..Time.current)
    @customer = @assignment.customer_context(context.member)
  end

  def call
    contracts = @customer.contracts.where(status: %w[active expiring])
    tickets = @customer.tickets.where(opened_at: @period)
    activities = @customer.activities.where(completed_at: @period)
    risks = @context.records(JrcRelationship::RiskCase).where(assignment: @assignment)
    qbrs = @context.records(JrcRelationship::Qbr).where(assignment: @assignment)
    signals = JrcRelationship::CustomerSignals.new(assignment: @assignment, context: @context).call
    plans = @context.records(JrcRelationship::SuccessPlan).where(assignment: @assignment)
    { _source_ids: signals[:_source_ids], formatting: @context.formatting, period: { from: @period.begin, to: @period.end }, health: signals[:health],
      mrr_cents: signals[:mrr_cents], finance_overdue_cents: signals[:overdue_cents],
      tickets: tickets.count, completed_activities: activities.completed.count,
      risks: risks.where.not(status: %w[retained churn no_action]).pluck(:id, :reason, :severity),
      contracts: contracts.includes(sales_order: :order_items).map { |row| { id: row.id, number: row.contract_number, ends_on: row.ends_on,
        monthly_cents: row.monthly_cents, products: row.sales_order.order_items.map { |item| [item.product_id, item.name] } } },
      projects: @customer.projects.order(:due_on).limit(50).pluck(:id, :name, :status, :due_on),
      plan_summaries: plans.limit(50).map { |plan| { id: plan.id, title: plan.title, status: plan.status,
        goals: plan.goals, milestones: plan.metadata['milestones'], target_on: plan.target_on,
        summary: "#{plan.title}: #{plan.goals.count { |goal| goal['status'] == 'completed' }}/#{plan.goals.size} objetivos concluídos; prazo #{plan.target_on}." } },
      tasks: @customer.project_tasks.order(:due_on, :id).limit(250).pluck(:id, :title),
      activities: @customer.activities.order(due_at: :desc).limit(250).pluck(:id, :title),
      linked_tickets: @customer.tickets.order(opened_at: :desc).limit(250).pluck(:id, :title),
      qbrs: qbrs.order(scheduled_at: :desc).limit(100).pluck(:id, :title),
      agenda_template: @context.configuration(@assignment).effective_rules['qbr_agenda_template'],
      executive_summary: "#{@assignment.label}: #{tickets.count} chamados e #{activities.completed.count} atividades concluídas no período; #{risks.where.not(status: %w[retained churn no_action]).count} riscos abertos." }
  end
end
