# Additional NICO boundary; native human policies and queries remain unchanged.
module JrcNico::MigrationVisibility
  PARENTS = {
    'JrcCrm::Deal' => { lead_id: 'JrcCrm::Lead' },
    'JrcCrm::Proposal' => { deal_id: 'JrcCrm::Deal' },
    'JrcCrm::Activity' => { lead_id: 'JrcCrm::Lead', deal_id: 'JrcCrm::Deal' },
    'JrcCrm::FollowUp' => { lead_id: 'JrcCrm::Lead', deal_id: 'JrcCrm::Deal' },
    'JrcCrm::SalesOrder' => { deal_id: 'JrcCrm::Deal' },
    'JrcCrm::Contract' => { sales_order_id: 'JrcCrm::SalesOrder', deal_id: 'JrcCrm::Deal' },
    'JrcCrm::Invoice' => { sales_order_id: 'JrcCrm::SalesOrder', contract_id: 'JrcCrm::Contract' },
    'JrcCrm::SalesCommission' => { sales_order_id: 'JrcCrm::SalesOrder' },
    'JrcCrm::BackofficeRequest' => { sales_order_id: 'JrcCrm::SalesOrder', contract_id: 'JrcCrm::Contract' },
    'Message' => { conversation_id: 'Conversation' }, 'CsatSurveyResponse' => { conversation_id: 'Conversation' },
    'Call' => { conversation_id: 'Conversation' }, 'JrcServiceDesk::TicketEvent' => { ticket_id: 'JrcServiceDesk::Ticket' },
    'JrcServiceDesk::SlaSnapshot' => { ticket_id: 'JrcServiceDesk::Ticket' },
    'JrcServiceDesk::SlaMilestone' => { ticket_id: 'JrcServiceDesk::Ticket', sla_snapshot_id: 'JrcServiceDesk::SlaSnapshot' },
    'JrcCampaigns::Recipient' => { conversation_id: 'Conversation' },
    'JrcProjects::Task' => { project_id: 'JrcProjects::Project' },
    'JrcOperations::Link' => { project_id: 'JrcProjects::Project', task_id: 'JrcProjects::Task', ticket_id: 'JrcServiceDesk::Ticket',
                               conversation_id: 'Conversation', crm_deal_id: 'JrcCrm::Deal' }
  }.freeze
  DOMAINS = {
    'JrcProjects::Project' => 'projects', 'JrcProjects::Task' => 'project_tasks',
    'JrcServiceDesk::Ticket' => 'service_desk_tickets', 'JrcServiceDesk::TicketEvent' => 'service_desk_events',
    'JrcServiceDesk::SlaSnapshot' => 'service_desk_sla_snapshots', 'JrcServiceDesk::SlaMilestone' => 'service_desk_sla_milestones'
  }.freeze
  ARGUMENTS = {
    'contact_id' => 'Contact', 'requester_id' => 'Contact', 'company_id' => 'JrcCustomers::Company',
    'lead_id' => 'JrcCrm::Lead', 'deal_id' => 'JrcCrm::Deal', 'proposal_id' => 'JrcCrm::Proposal',
    'sales_order_id' => 'JrcCrm::SalesOrder', 'contract_id' => 'JrcCrm::Contract',
    'ticket_id' => 'JrcServiceDesk::Ticket', 'project_id' => 'JrcProjects::Project', 'assignment_id' => 'JrcRelationship::Assignment',
    'task_id' => 'JrcProjects::Task', 'parent_id' => 'JrcProjects::Task', 'before_task_id' => 'JrcProjects::Task'
  }.freeze

  def self.contacts(account)
    JrcMigrations::Visibility.scope(account.contacts, account: account, domain: 'contacts')
  end

  def self.companies(account)
    JrcMigrations::Visibility.scope(JrcCustomers::Company.all, account: account, domain: 'companies')
  end

  def self.scope(relation, account:)
    JrcNico::MigrationScope.new(relation, account: account).call
  end

  def self.authorize!(record, account:)
    return record if record.is_a?(Account) && record.id == account.id

    ActiveRecord::Base.uncached do
      current = scope(record.class, account: account).find(record.id)
      JrcNico::MigrationEvidence.authorize!(current, account: account)
    end
  end

  def self.visible?(record, account:)
    authorize!(record, account: account)
    true
  rescue ActiveRecord::RecordNotFound
    false
  end

  def self.campaign!(campaign, account:)
    authorize!(campaign, account: account)
    JrcNico::MigrationCampaignEvidence.new(campaign, account: account).call
  end

  def self.campaign_visible?(campaign, account:)
    campaign!(campaign, account: account)
    true
  rescue ActiveRecord::RecordNotFound
    false
  end

  def self.arguments!(arguments, account:)
    ARGUMENTS.each do |key, type|
      scope(type.constantize, account: account).find(arguments[key]) if arguments[key].present?
    end
    return if arguments['conversation_id'].blank?

    scope(Conversation, account: account).find_by!(display_id: arguments['conversation_id'])
  end
end
