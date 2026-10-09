class JrcRelationship::WorkContext
  def initialize(context:, assignment:, period: nil)
    @context = context
    @assignment = context.assignment(assignment.id)
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
      contracts: contract_summaries(contracts),
      projects: @customer.projects.order(:due_on).limit(50).pluck(:id, :name, :status, :due_on),
      plan_summaries: plan_summaries(plans),
      tasks: @customer.project_tasks.order(:due_on, :id).limit(250).pluck(:id, :title),
      activities: @customer.activities.order(due_at: :desc).limit(250).pluck(:id, :title),
      linked_tickets: @customer.tickets.order(opened_at: :desc).limit(250).pluck(:id, :title),
      qbrs: qbrs.order(scheduled_at: :desc).limit(100).pluck(:id, :title),
      **commercial_options,
      agenda_template: @context.configuration(@assignment).effective_rules['qbr_agenda_template'],
      executive_summary: "#{@assignment.label}: #{tickets.count} chamados e #{activities.completed.count} atividades concluídas no período; #{risks.where.not(status: %w[retained churn no_action]).count} riscos abertos." }
  end

  private

  def commercial_options
    { deals: @customer.deals.order(id: :desc).limit(250).map do |deal|
      { id: deal.id, title: deal.title, contact_id: deal.contact_id, company_id: deal.company_id }
    end,
      contacts: @customer.contacts.order(:name).limit(250).pluck(:id, :name), handoff_sources: handoff_sources }
  end

  def plan_summaries(plans)
    plans.limit(50).map do |plan|
      completed = plan.goals.count { |goal| goal['status'] == 'completed' }
      { id: plan.id, title: plan.title, status: plan.status, goals: plan.goals, milestones: plan.metadata['milestones'], target_on: plan.target_on,
        summary: "#{plan.title}: #{completed}/#{plan.goals.size} objetivos concluídos; prazo #{plan.target_on}." }
    end
  end

  def contract_summaries(contracts)
    contracts.includes(:contract_items, sales_order: :order_items).map do |row|
      products = (row.sales_order.order_items + row.contract_items).map { |item| [item.product_id, item.name] }.uniq
      { id: row.id, number: row.contract_number, ends_on: row.ends_on, monthly_cents: row.monthly_cents, products: products }
    end
  end

  def handoff_sources
    orders = @customer.orders.where(status: 'completed').order(:id).limit(100).select do |order|
      JrcRelationship::Eligibility.new(order, exception: @assignment.settings['eligibility_exception']).reason.nil?
    end
    orders.map { |order| { type: order.class.name, id: order.id, label: order.order_number } } +
      @customer.projects.where(status: 'completed').order(:id).limit(100).map do |project|
        { type: project.class.name, id: project.id, label: project.name }
      end
  end
end
