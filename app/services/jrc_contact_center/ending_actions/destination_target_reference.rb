# frozen_string_literal: true

# Native read authority only. A successful immutable receipt remains successful
# after access is revoked; its target link is withheld instead of rewriting it.
class JrcContactCenter::EndingActions::DestinationTargetReference
  def initialize(member:)
    @member = member
    @account = member.account
  end

  def call(execution)
    return unless execution && execution.account_id == @account.id

    case [execution.destination_kind, execution.operation, execution.target_type]
    when ['project_task', 'create_task', 'JrcProjects::Task'] then project_task(execution.target_id)
    when ['crm', 'create_lead', 'JrcCrm::Lead'] then crm_record(execution.target_id, :lead)
    when ['crm', 'create_activity', 'JrcCrm::Activity'] then crm_record(execution.target_id, :activity)
    when ['service_desk', 'create_ticket', 'JrcServiceDesk::Ticket'], ['service_desk', 'update_ticket', 'JrcServiceDesk::Ticket']
      service_desk_ticket(execution.target_id)
    end
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    nil
  end

  private

  def project_task(identifier)
    task = JrcProjects::Task.where(account: @account).find(identifier)
    project = JrcOperations::Access.projects(@member).find(task.project_id)
    raise Pundit::NotAuthorizedError unless JrcProjects::Authorization.allowed?(
      account_user: @member, capability: 'projects.task.view', project: project
    )

    { kind: 'project_task', id: task.id.to_s, project_id: project.id.to_s }
  end

  def crm_record(identifier, kind)
    raise Pundit::NotAuthorizedError unless @account.feature_enabled?('jrc_crm')

    # The native CRM controller independently checks module access, owner and
    # OrganizationalVisibility. ResourceScope enforces these same native rules.
    scope = JrcDomainCommands::ResourceScope.new(account: @account, user: @member.user)
    relation = kind == :lead ? @account.jrc_crm_leads : @account.jrc_crm_activities
    record = scope.authorize!(relation.find(identifier))
    { kind: kind == :lead ? 'crm_lead' : 'crm_activity', id: record.id.to_s }
  end

  def service_desk_ticket(identifier)
    context = JrcServiceDesk::OperationalContext.new(account: @account, account_user: @member, user: @member.user)
    policy = JrcServiceDesk::TicketPolicy
    record = policy::Scope.new(context.to_h, JrcServiceDesk::Ticket).resolve.find(identifier)
    raise Pundit::NotAuthorizedError unless policy.new(context.to_h, record).show?

    { kind: 'service_desk_ticket', id: record.id.to_s }
  end
end
