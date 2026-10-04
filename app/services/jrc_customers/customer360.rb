class JrcCustomers::Customer360
  attr_reader :contacts, :conversations, :deals, :leads, :activities, :proposals, :audits, :calls, :recipients, :tickets, :projects, :project_tasks, :ticket_events, :project_events, :contracts, :orders, :follow_ups

  def initialize(account:, user:, account_user:, company: nil, contact: nil)
    @account, @user, @company, @contact = account, user, company, contact
    raise ArgumentError, 'Choose exactly one company or contact' if company.nil? == contact.nil?
    raise ActiveRecord::RecordNotFound unless (company || contact).account_id == account.id

    @visibility = JrcCustomers::Visibility.new(account: account, user: user, account_user: account_user)
    @contacts = contact ? account.contacts.where(id: contact.id) : account.contacts.where(company_id: company.id)
    contact_ids = @contacts.select(:id)
    @conversations = @visibility.conversations.where(contact_id: contact_ids)
    @deals = related(@visibility.crm(account.jrc_crm_deals), contact_ids)
    @leads = related(@visibility.crm(account.jrc_crm_leads), contact_ids)
    @activities = related(@visibility.crm(account.jrc_crm_activities, owner: :user_id), contact_ids)
    @activities = @activities.or(@visibility.crm(account.jrc_crm_activities, owner: :user_id).where(deal_id: deals.select(:id)))
    @activities = @activities.or(@visibility.crm(account.jrc_crm_activities, owner: :user_id).where(lead_id: leads.select(:id)))
    @proposals = @visibility.crm(JrcCrm::Proposal.where(account_id: account.id)).where(deal_id: deals.select(:id))
    @calls = @visibility.calls(contact_ids: contact_ids, conversation_ids: conversations.select(:id))
    @recipients = if @visibility.campaigns?
                    JrcCampaigns::Recipient.where(contact_id: contact_ids, campaign_id: account.jrc_campaigns.select(:id))
                  end
    initialize_operations(contact_ids)
    initialize_commercial(contact_ids)
    initialize_audits
  end

  def overview
    values = {
      contacts: contacts.count, conversations_open: conversations.where(status: :open).count,
      capabilities: { conversations: true, crm: @visibility.crm?, calls: !calls.nil?, campaigns: !recipients.nil?,
                      service_desk: @visibility.service_desk?, projects: @visibility.projects?, contracts: @visibility.crm?, central_sip_cdr: false },
      visibility: 'Counts and items are restricted to the signed-in user. Missing modules are not counted as zero.'
    }
    if @visibility.crm?
      open_deals = deals.where(status: 'open')
      active_contracts = contracts.where(status: %w[active expiring])
      next_activity = activities.pending.where.not(due_at: nil).where('due_at >= ?', Time.current).order(:due_at, :id).first
      values.merge!(
        opportunities: open_deals.count,
        opportunities_value_cents: open_deals.sum(:value_cents),
        leads: leads.count,
        proposals: proposals.count,
        pending_activities: activities.pending.count,
        contracts_active: active_contracts.count,
        contracts_mrr_cents: active_contracts.sum(:monthly_cents),
        next_activity: next_activity && { id: next_activity.id, title: next_activity.title, due_at: next_activity.due_at&.iso8601 }
      )
    end
    if @visibility.service_desk?
      values[:tickets_open] = tickets.joins(:status).where(jrc_service_desk_ticket_statuses: { phase: %w[open waiting] }).count
      values[:sla_breached] = JrcServiceDesk::SlaClock.where(account_id: @account.id, ticket_id: tickets.select(:id))
                                                      .where(state: %w[running paused]).where('due_at < ?', Time.current)
                                                      .select(:ticket_id).distinct.count
    end
    values[:projects_active] = projects.where(status: %w[planned active on_hold]).count if @visibility.projects?
    last_conversation_at = Message.where(account_id: @account.id, conversation_id: conversations.select(:id), private: false)
                                  .where(message_type: [0, 1]).maximum(:created_at)
    interactions = [last_conversation_at, activities.maximum(:completed_at), calls&.maximum(:started_at),
                    ticket_events.maximum(:created_at), project_events.maximum(:created_at)]
    values[:last_conversation_at] = last_conversation_at&.iso8601
    values[:last_interaction_at] = interactions.compact.max&.iso8601
    values
  end

  def sources
    result = { 'conversations' => conversations, 'leads' => leads, 'deals' => deals,
               'proposals' => proposals, 'activities' => activities }
    result['tickets'] = tickets if @visibility.service_desk?
    if @visibility.projects?
      result['projects'] = projects
      result['project_tasks'] = project_tasks
    end
    if @visibility.crm?
      result['contracts'] = contracts
      result['orders'] = orders
      result['follow_ups'] = follow_ups
    end
    result['calls'] = calls if calls
    result['campaigns'] = recipients if recipients
    result
  end

  def timeline_sources
    result = {
      'message' => [Message.where(account_id: @account.id, conversation_id: conversations.select(:id), private: false)
                            .where(message_type: [0, 1]), :created_at],
      'audit' => [audits, :created_at],
      'activity_created' => [activities, :created_at],
      'activity_completed' => [activities.where.not(completed_at: nil), :completed_at]
    }
    result['ticket_event'] = [ticket_events, :created_at] if @visibility.service_desk?
    result['project_event'] = [project_events, :created_at] if @visibility.projects?
    result['call'] = [calls.where.not(started_at: nil), :started_at] if calls
    result['campaign_sent'] = [recipients.where.not(sent_at: nil), :sent_at] if recipients
    result
  end

  def resource_key
    @company ? "company:#{@company.id}" : "contact:#{@contact.id}"
  end

  private

  def initialize_operations(contact_ids)
    ticket_scope = @visibility.tickets
    @tickets = if @contact
                 ticket_scope.where(requester_id: contact_ids)
               else
                 ticket_scope.where(company_id: @company.id).or(ticket_scope.where(company_id: nil, requester_id: contact_ids))
               end
    @projects = related(@visibility.projects, contact_ids)
    @project_tasks = @visibility.project_tasks(@projects)
    @ticket_events = @visibility.ticket_events(@tickets).where(event_type: %w[ticket_created ticket_updated lifecycle_transitioned])
    audit = JrcProjects::AuditEvent.where(account_id: @account.id)
    @project_events = audit.where(auditable_type: 'JrcProjects::Project', auditable_id: @projects.select(:id))
    @project_events = @project_events.or(audit.where(auditable_type: 'JrcProjects::Task', auditable_id: @project_tasks.select(:id)))
    # Do not disclose budgets, private notes, attachments or IDs of hidden origins.
    @project_events = @project_events.where(action: %w[projects.project.created projects.project.updated projects.task.created projects.task.updated projects.task.moved projects.task.completed])
  end

  def initialize_commercial(contact_ids)
    orders_scope = @visibility.crm(JrcCrm::SalesOrder.where(account_id: @account.id))
    @orders = orders_scope.where(contact_id: contact_ids).or(orders_scope.where(deal_id: deals.select(:id)))
    contracts_scope = @visibility.crm(JrcCrm::Contract.where(account_id: @account.id))
    @contracts = contracts_scope.where(contact_id: contact_ids).or(contracts_scope.where(deal_id: deals.select(:id)))
    @contracts = @contracts.or(contracts_scope.where(sales_order_id: orders.select(:id)))
    scope = @visibility.crm(JrcCrm::FollowUp.where(account_id: @account.id), owner: :user_id)
    @follow_ups = scope.where(deal_id: deals.select(:id)).or(scope.where(lead_id: leads.select(:id)))
  end

  def related(scope, contact_ids)
    return scope.where(contact_id: contact_ids) if @contact

    scope.where(company_id: @company.id).or(scope.where(company_id: nil, contact_id: contact_ids))
  end

  def initialize_audits
    scope = JrcCrm::AuditEvent.where(account_id: @account.id)
    @audits = scope.where(resource_type: 'Contact', resource_id: contacts.select(:id))
    @audits = @audits.or(scope.where(resource_type: 'Company', resource_id: @company.id)) if @company
    { deals => ['JrcCrm::Deal', 'Deal'], leads => ['JrcCrm::Lead', 'Lead'], proposals => ['JrcCrm::Proposal', 'Proposal'], contracts => ['JrcCrm::Contract'], orders => ['JrcCrm::SalesOrder'] }.each do |records, types|
      @audits = @audits.or(scope.where(resource_type: types, resource_id: records.select(:id)))
    end
  end
end
