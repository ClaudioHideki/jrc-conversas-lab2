class JrcRelationship::PlaybookFlowLocks
  def self.acquire!(reference, execution: nil, exclusive_account: false)
    JrcRelationship::Assignment.lock('FOR SHARE').find(reference.assignment.id)
    Account.lock(exclusive_account ? 'FOR UPDATE' : 'FOR SHARE').find(reference.context.account.id)
    member_sources!(reference)
    grant_sources!(reference)
    customer_sources!(reference)
    published_sources!(reference, execution)
  end

  def self.member_sources!(reference)
    members = AccountUser.where(id: reference.context.member.id).or(
      AccountUser.where(account_id: reference.context.account.id, user_id: reference.flow.created_by_id)
    )
    members.order(:id).lock('FOR SHARE').load
  end

  def self.customer_sources!(reference)
    mode = reference.policy.definition.fetch('phase') == 3 ? 'FOR UPDATE' : 'FOR SHARE'
    Contact.lock(mode).find(reference.contact.id)
    Message.lock('FOR SHARE').find(reference.input_message.id) if reference.input_message
    ContactInbox.lock('FOR SHARE').find(reference.conversation.contact_inbox_id)
    Inbox.lock('FOR SHARE').find(reference.conversation.inbox_id)
    company_unit_sources!(reference)
    JrcRelationship::Configuration.where(account_id: reference.context.account.id).order(:id).lock('FOR SHARE').load
  end

  def self.company_unit_sources!(reference)
    company_id = reference.assignment.company_id || reference.contact.company_id
    JrcCustomers::Company.lock('FOR SHARE').find(company_id) if company_id
    JrcCrm::BusinessUnit.lock('FOR SHARE').find(reference.assignment.business_unit_id) if reference.assignment.business_unit_id
  end

  def self.grant_sources!(reference)
    account = reference.context.account
    user = reference.context.user
    CustomRole.lock('FOR SHARE').find(reference.context.member.custom_role_id) if reference.context.member.custom_role_id
    TeamMember.where(team_id: account.teams.select(:id), user_id: user.id).order(:id).lock('FOR SHARE').load
    native_grants!(reference)
  end

  def self.native_grants!(reference)
    account = reference.context.account
    user = reference.context.user
    JrcServiceDesk::UnitMembership.where(account_id: account.id, account_user_id: reference.context.member.id).order(:id).lock('FOR SHARE').load
    JrcProjects::ProjectMember.where(account_id: account.id, user_id: user.id).order(:id).lock('FOR SHARE').load
    inbox_unit_grants!(account, user)
  end

  def self.inbox_unit_grants!(account, user)
    InboxMember.where(inbox_id: account.inboxes.select(:id), user_id: user.id).order(:id).lock('FOR SHARE').load
    account.jrc_crm_user_business_units.where(user_id: user.id).order(:id).lock('FOR SHARE').load
  end

  def self.published_sources!(reference, execution)
    JrcFlow.lock('FOR SHARE').find(reference.flow.id)
    return unless execution

    JrcRelationship::PlaybookExecution.lock('FOR SHARE').find(execution.id)
    JrcRelationship::Playbook.lock('FOR SHARE').find(execution.playbook_id)
    JrcRelationship::PlaybookVersion.where(playbook_id: execution.playbook_id, version: execution.version).lock('FOR SHARE').load
  end
end
