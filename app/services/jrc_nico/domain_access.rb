# Native policies remain the authority for both execution and saved-result access.
class JrcNico::DomainAccess
  RESOURCE_TYPES = %w[JrcServiceDesk::Ticket JrcServiceDesk::TicketNote JrcServiceDesk::LifecycleTransition
                      JrcProjects::Project JrcProjects::Task JrcOperations::Link JrcCrm::SalesOrder
                      JrcCrm::Contract JrcCrm::SalesCommission JrcCrm::BackofficeRequest
                      JrcCrm::SalesGoal JrcCrm::CommissionProgram JrcCrm::FollowUp
                      JrcNico::ServiceDeskContext JrcNico::ServiceDeskLookup JrcNico::ServiceDeskRequesters
                      JrcNico::ServiceDeskAssignee JrcNico::ServiceDeskAssignable JrcNico::ServiceDeskTeams JrcNico::ServiceDeskUnit
                      JrcNico::ServiceTicketLifecycle JrcNico::ServiceTicketSla JrcNico::ServiceTicketCustomer
                      JrcNico::ServiceTicketNotes JrcNico::ServiceTicketConversations JrcNico::ProjectTasks Team
                      JrcServiceDesk::Unit JrcServiceDesk::OperatorCompany JrcServiceDesk::Queue
                      JrcServiceDesk::Priority JrcServiceDesk::Category JrcServiceDesk::TicketStatus].freeze

  def initialize(access)
    @access = access.authorize!
  end

  def context
    { account: @access.account, user: @access.user, account_user: @access.membership }
  end

  def available?(group)
    case group
    when 'service_desk'
      JrcServiceDesk::ModulePolicy.new(context, @access.account).show?
    when 'projects'
      JrcProjects::Authorization.allowed?(account_user: @access.membership, capability: 'projects.project.view')
    when 'projects_create'
      JrcProjects::Authorization.allowed?(account_user: @access.membership, capability: 'projects.project.create')
    else true
    end
  end

  def project(id, capability: 'projects.project.view')
    record = JrcOperations::Access.projects(@access.membership).find(id)
    authorize_project!(record, capability)
    record
  end

  def task(project_id, id, capability: 'projects.task.view')
    project = project(project_id)
    record = project.tasks.where(account_id: @access.account.id).find(id)
    authorize_project!(project, capability, record)
    record
  end

  def authorize_project!(project, capability, record = nil)
    return if JrcProjects::Authorization.allowed?(account_user: @access.membership, capability: capability, project: project, record: record)

    raise Pundit::NotAuthorizedError
  end

  def ticket(id)
    JrcOperations::Access.ticket!(@access.membership, id)
  end

  def self.authorize_resource!(access, type, id)
    domain = new(access)
    case type
    when 'JrcNico::ServiceDeskContext', 'JrcNico::ServiceDeskLookup', 'JrcNico::ServiceDeskRequesters', 'JrcNico::ServiceDeskTeams'
      raise Pundit::NotAuthorizedError unless id.to_i == access.account.id && domain.available?('service_desk')
      unless type == 'JrcNico::ServiceDeskContext'
        Pundit.authorize(domain.context, :lookup, :index?, policy_class: JrcServiceDesk::LookupPolicy)
      end
      if type == 'JrcNico::ServiceDeskRequesters'
        raise Pundit::NotAuthorizedError unless JrcServiceDesk::OperationalContext.new(domain.context).capability?(:customers_view)

        Pundit.authorize(domain.context, Contact, :index?)
      elsif type == 'JrcNico::ServiceDeskTeams'
        Pundit.authorize(domain.context, Team, :index?)
      end
      access.account
    when 'JrcNico::ServiceDeskAssignee', 'JrcNico::ServiceDeskAssignable'
      # UnitMembership has no administrative read API. Match the native Presenter
      # and, for lookup results, CatalogQuery's eligibility check instead.
      native = JrcServiceDesk::OperationalContext.new(domain.context)
      units = type == 'JrcNico::ServiceDeskAssignable' ? native.view_unit_scope : native.unit_scope
      record = JrcServiceDesk::UnitMembership.where(account_id: access.account.id, unit_id: units.select(:id)).find(id)
      raise Pundit::NotAuthorizedError unless record.account_user.account_id == access.account.id

      if type == 'JrcNico::ServiceDeskAssignable'
        target = JrcServiceDesk::OperationalContext.new(account: access.account, user: record.account_user.user, account_user: record.account_user)
        raise Pundit::NotAuthorizedError unless record.active? && target.capability?(:tickets_view)
      end
      record
    when 'JrcNico::ServiceDeskUnit'
      JrcServiceDesk::OperationalContext.new(domain.context).view_unit_scope.find(id)
    when 'Team'
      record = access.account.teams.find(id)
      Pundit.authorize(domain.context, record, :show?)
    when 'JrcNico::ServiceTicketLifecycle'
      ticket = domain.ticket(id)
      Pundit.authorize(domain.context, ticket, :inspect?, policy_class: JrcServiceDesk::LifecycleActionPolicy)
      ticket
    when 'JrcNico::ServiceTicketSla', 'JrcNico::ServiceTicketCustomer', 'JrcNico::ServiceTicketNotes', 'JrcNico::ServiceTicketConversations'
      ticket = domain.ticket(id)
      action = { 'JrcNico::ServiceTicketSla' => :view_sla?, 'JrcNico::ServiceTicketCustomer' => :view_customer?,
                 'JrcNico::ServiceTicketNotes' => :view_notes?, 'JrcNico::ServiceTicketConversations' => :view_conversations? }.fetch(type)
      Pundit.authorize(domain.context, ticket, action)
      ticket
    when 'JrcServiceDesk::Unit', 'JrcServiceDesk::OperatorCompany', 'JrcServiceDesk::Queue',
         'JrcServiceDesk::Priority', 'JrcServiceDesk::Category', 'JrcServiceDesk::TicketStatus'
      model = JrcServiceDesk::CatalogQuery::MODELS.values.find { |candidate| candidate.name == type }
      record = Pundit.policy_scope!(domain.context, model).find(id)
      Pundit.authorize(domain.context, record, :show?)
    when 'JrcServiceDesk::Ticket' then domain.ticket(id)
    when 'JrcServiceDesk::TicketNote'
      record = JrcServiceDesk::TicketNote.where(account_id: access.account.id).find(id)
      domain.ticket(record.ticket_id)
      Pundit.authorize(domain.context, record, :show?)
    when 'JrcServiceDesk::LifecycleTransition'
      record = JrcServiceDesk::LifecycleTransition.where(account_id: access.account.id).find(id)
      ticket = domain.ticket(record.ticket_id)
      Pundit.authorize(domain.context, ticket, :view_history?)
      Pundit.authorize(domain.context, ticket, :inspect?, policy_class: JrcServiceDesk::LifecycleActionPolicy)
      record
    when 'JrcProjects::Project' then domain.project(id)
    when 'JrcNico::ProjectTasks' then domain.project(id, capability: 'projects.task.view')
    when 'JrcProjects::Task'
      record = JrcProjects::Task.where(account_id: access.account.id).find(id)
      domain.task(record.project_id, record.id)
    when 'JrcOperations::Link'
      record = JrcOperations::Link.where(account_id: access.account.id).find(id)
      JrcOperations::Linker.new(account_user: access.membership).read(record)
      record
    when 'JrcCrm::SalesOrder' then access.crm_scope(JrcCrm::SalesOrder).find(id)
    when 'JrcCrm::Contract' then access.crm_scope(JrcCrm::Contract).find(id)
    when 'JrcCrm::SalesCommission' then access.crm_scope(JrcCrm::SalesCommission, owner: :user_id).find(id)
    when 'JrcCrm::BackofficeRequest' then access.crm_scope(JrcCrm::BackofficeRequest).find(id)
    when 'JrcCrm::FollowUp' then access.crm_scope(JrcCrm::FollowUp, owner: :user_id).find(id)
    when 'JrcCrm::SalesGoal', 'JrcCrm::CommissionProgram'
      raise Pundit::NotAuthorizedError unless access.crm? && access.membership.administrator?

      model = type == 'JrcCrm::SalesGoal' ? JrcCrm::SalesGoal : JrcCrm::CommissionProgram
      model.where(account_id: access.account.id).find(id)
    else raise Pundit::NotAuthorizedError
    end
  end
end
