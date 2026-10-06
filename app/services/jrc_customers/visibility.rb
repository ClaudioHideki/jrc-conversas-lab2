# SQL scopes mirror native ConversationPolicy and CRM controller ownership.
# Re-evaluated for every request and used for BOTH totals and list/timeline items.
class JrcCustomers::Visibility
  def initialize(account:, user:, account_user:)
    @account, @user, @membership = account, user, account_user
  end

  def conversations
    # Use the source-of-truth permission filter, including its enterprise/custom-role extension.
    Conversations::PermissionFilterService.new(@account.conversations, @user, @account).perform
  end

  def calls(contact_ids:, conversation_ids:)
    return nil unless defined?(::Call)

    scope = ::Call.where(account_id: @account.id, contact_id: contact_ids, conversation_id: conversation_ids)
    # Match native CallFinder: ordinary agents may see only calls they handled.
    account_wide = @membership.administrator? || Array(@membership.custom_role&.permissions).include?('report_manage')
    account_wide ? scope : scope.where(accepted_by_agent_id: @user.id)
  end

  def crm(relation, owner: :owner_id)
    return relation.none unless crm?
    return relation if @membership.administrator?

    JrcCrm::OrganizationalVisibility.new(account: @account, user: @user, relation: relation.where(owner => @user.id)).call
  end

  def crm?
    @account.feature_enabled?('jrc_crm') && @membership.permissions.include?('jrc_crm')
  end

  def service_desk?
    service_desk_context.capability?(:tickets_view) && service_desk_context.capability?(:customers_view)
  end

  def tickets
    return JrcServiceDesk::Ticket.none unless service_desk?

    JrcServiceDesk::TicketPolicy::Scope.new(service_desk_context.to_h, JrcServiceDesk::Ticket).resolve
  end

  def ticket_events(ticket_scope)
    scope = JrcServiceDesk::TicketEvent.where(account_id: @account.id, ticket_id: ticket_scope.select(:id))
    service_desk_context.capability?(:history_view) ? scope : scope.none
  end

  def projects?
    JrcOperations::Access.project_access?(@membership) &&
      JrcProjects::Authorization.allowed?(account_user: @membership, capability: 'projects.project.view')
  end

  def projects
    JrcOperations::Access.projects(@membership)
  end

  def project_tasks(project_scope)
    scope = JrcProjects::Task.where(account_id: @account.id, project_id: project_scope.select(:id))
    if @membership.custom_role_id.present? && !Array(@membership.custom_role&.permissions).include?('jrc_projects_task_view')
      return scope.none
    end
    scope
  end

  def service_desk_context
    @service_desk_context ||= JrcServiceDesk::OperationalContext.new(account: @account, user: @user, account_user: @membership)
  end

  def campaigns?
    @membership.administrator? && @account.feature_enabled?('jrc_campaigns')
  end
end
