# Every link is selected from the customer's currently authorized native scope.
class JrcRelationship::ActionSources
  def initialize(context, record)
    @context, @record = context, record
    @customer = record.assignment.customer_context(context.member)
  end

  def call
    sources = []
    sources << link('activity', @record.activity_id, 'crm_activities', query: { activityId: @record.activity_id }) if
      @record.activity_id && @customer.activities.exists?(id: @record.activity_id)
    case @record.kind
    when 'finance'
      visibility = JrcCustomers::Visibility.new(account: @context.account, user: @context.user, account_user: @context.member)
      invoices = JrcCrm::Invoice.where(account_id: @context.account.id, contract_id: @customer.contracts.select(:id)).or(
        JrcCrm::Invoice.where(account_id: @context.account.id, sales_order_id: @customer.orders.select(:id)))
      invoices = JrcCrm::OrganizationalVisibility.new(account: @context.account, user: @context.user, relation: invoices).call unless @context.policy.admin?
      if visibility.crm?
        invoices.where.not(status: %w[paid canceled]).where('due_on < ? AND balance_cents > 0', Date.current).limit(5).pluck(:id).each do |id|
          # Invoice detail lives inside the real order, not a parallel CS invoice.
          invoice = invoices.find(id)
          if invoice.contract_id && @customer.contracts.exists?(id: invoice.contract_id)
            sources << link('invoice', id, 'crm_contracts', query: { contractId: invoice.contract_id })
          elsif invoice.sales_order_id && @customer.orders.exists?(id: invoice.sales_order_id)
            sources << link('invoice', id, 'crm_orders', query: { orderId: invoice.sales_order_id })
          end
        end
      end
    when 'renewal'
      id = @record.source_key.to_s.split(':')[1] if @record.source_key.to_s.start_with?('renewal:')
      @customer.contracts.where(id: id).pluck(:id).each { |value| sources << link('contract', value, 'crm_contracts', query: { contractId: value }) }
    when 'ticket', 'recurring_ticket', 'post_ticket'
      ids = Array(@record.metadata.dig('_source_ids', 'tickets'))
      id = @record.source_key.to_s.split(':')[1] if @record.source_key.to_s.start_with?('post-ticket:')
      tickets = @customer.tickets.where(id: id || ids)
      tickets = tickets.where(opened_at: 30.days.ago..Time.current) if @record.kind == 'recurring_ticket'
      if @record.kind == 'ticket'
        rules = @context.configuration(@record.assignment).effective_rules
        critical = tickets.joins(:status, :priority).where(jrc_service_desk_ticket_statuses: { phase: %w[open waiting] },
          jrc_service_desk_priorities: { code: rules['critical_priority_codes'] }).select(:id)
        breached = JrcServiceDesk::SlaClock.where(account_id: @context.account.id, ticket_id: tickets.select(:id),
          state: %w[running paused]).where('due_at < ?', Time.current).select(:ticket_id)
        tickets = tickets.where(id: critical).or(tickets.where(id: breached))
      end
      tickets.limit(5).pluck(:id).each do |value|
        sources << link('ticket', value, 'jrc_service_desk_detail', params: { ticketId: value })
      end
    when 'onboarding'
      @customer.projects.where('due_on < ?', Date.current).where.not(status: %w[completed canceled]).limit(5).pluck(:id).each do |id|
        sources << link('project', id, 'jrc_projects_detail', params: { projectId: id })
      end
      @customer.project_tasks.where('due_on < ?', Date.current).where.not(status: %w[completed canceled]).limit(5).pluck(:id, :project_id).each do |id, project|
        sources << link('project_task', id, 'jrc_projects_detail', params: { projectId: project }, query: { taskId: id })
      end
      id = @record.metadata['source_id']
      if @record.metadata['source_type'] == 'JrcCrm::SalesOrder' && @customer.orders.exists?(id: id)
        sources << link('order', id, 'crm_orders', query: { orderId: id })
      end
    when 'activity'
      @customer.activities.overdue.limit(5).pluck(:id).each { |id| sources << link('activity', id, 'crm_activities', query: { activityId: id }) }
    when 'satisfaction'
      @context.records(JrcRelationship::Survey).where(assignment_id: @record.assignment_id,
        id: Array(@record.metadata.dig('_source_ids', 'surveys'))).where.not(responded_at: nil).limit(5).pluck(:id).each do |id|
        sources << link('survey', id, 'jrc_relationship_surveys', query: { assignment_id: @record.assignment_id })
      end
      CsatSurveyResponse.where(account_id: @context.account.id, conversation_id: @customer.conversations.select(:id),
        id: Array(@record.metadata.dig('_source_ids', 'csat'))).includes(:conversation).limit(5).each do |response|
        sources << link('csat_survey_response', response.id, 'inbox_conversation', params: { conversation_id: response.conversation.display_id })
      end
    when 'expansion'
      id = @record.source_key.to_s.split(':')[1]
      if @context.records(JrcRelationship::ExpansionSignal).where(assignment_id: @record.assignment_id).exists?(id: id)
        sources << link('expansion', id, 'jrc_relationship_expansion', query: { assignment_id: @record.assignment_id })
      end
    end
    # Health, cadence and manually entered cases have a real portfolio origin.
    sources << link('customer', @record.assignment_id, 'jrc_relationship_health',
      query: { assignment_id: @record.assignment_id, customer: @record.assignment_id })
    sources.uniq { |source| [source[:kind], source[:id]] }
  end

  private

  def link(kind, id, name, params: {}, query: {})
    { kind: kind, id: id, route: { name: name, params: params.merge(accountId: @context.account.id), query: query } }
  end
end
