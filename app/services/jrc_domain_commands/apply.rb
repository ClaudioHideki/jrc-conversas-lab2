class JrcDomainCommands::Apply
  def initialize(authority, conversation, input, arguments)
    @authority = authority
    @account = authority.account
    @conversation = conversation
    @input = input
    @arguments = arguments
  end

  def call
    raise ArgumentError, 'domain_unavailable' unless JrcDomainCommands::Request.available?

    result = if @arguments.fetch('command') == 'create_lead'
               native_lead
             else
               { lead: create_activity, created: true }
             end
    record = result.fetch(:lead)
    { 'command' => @arguments.fetch('command'), 'resource_type' => record.class.name, 'resource_id' => record.id,
      'created' => result.fetch(:created), 'delivery' => 'NOT_APPLICABLE',
      'event' => { 'id' => @input.fetch('operation_id'), 'causation_id' => @input.fetch('operation_id'),
                   'type' => record.is_a?(JrcCrm::Lead) ? 'crm.lead.ready' : 'crm.activity.created' } }
  end

  private

  def native_lead
    scope = JrcDomainCommands::ResourceScope.new(account: @account, user: @authority.user)
    existing = @account.jrc_crm_leads.where(idempotency_key: "conversation:#{@conversation.id}")
    existing = existing.or(@account.jrc_crm_leads.where(conversation_id: @conversation.id)).lock.first
    return { lead: scope.authorize!(existing), created: false } if existing

    unit_id = scope.new_lead_unit
    result = JrcCrm::ConversationLeadService.new(account: @account, conversation: @conversation, actor: @authority.user).call
    lead = result.fetch(:lead)
    lead.update!(business_unit_id: unit_id) if result.fetch(:created) && unit_id
    scope.authorize!(lead)
    JrcDomainCommands::ResourceScope.new(account: @account, user: lead.owner).authorize!(lead)
    result
  end

  def create_activity
    owner = activity_owner
    due_at = activity_deadline
    kind = @arguments.fetch('command') == 'create_meeting' ? 'meeting' : 'task'
    fence_meeting(owner, due_at) if kind == 'meeting'
    lead = native_lead.fetch(:lead)
    owner_scope = JrcDomainCommands::ResourceScope.new(account: @account, user: owner)
    owner_scope.authorize!(lead)
    activity = @account.jrc_crm_activities.new(user: owner, contact: @conversation.contact, conversation: @conversation,
                                               lead: lead, business_unit_id: lead.business_unit_id, company_id: lead.company_id,
                                               title: @arguments.fetch('title'), due_at: due_at, activity_type: kind)
    result = JrcCrm::ActivityDispatchService.new(activity: activity, actor: @authority.user).call
    raise ArgumentError, 'domain_activity_rejected' unless result.fetch(:success)

    JrcDomainCommands::ResourceScope.new(account: @account, user: @authority.user).authorize!(activity)
    owner_scope.authorize!(activity)
    activity
  end

  def activity_owner
    member = @account.account_users.lock('FOR SHARE').find_by!(user_id: @arguments.fetch('owner_id'))
    owner = User.lock('FOR SHARE').find(member.user_id)
    CustomRole.lock('FOR SHARE').find(member.custom_role_id) if member.custom_role_id
    raise Pundit::NotAuthorizedError unless JrcOperations::Access.crm?(member) && owner.active_for_authentication? && owner.confirmed?

    owner
  end

  def activity_deadline
    due_at = Time.iso8601(@arguments.fetch('due_at'))
    raise ArgumentError, 'domain_due_at' unless due_at > Time.current && due_at <= 366.days.from_now

    due_at
  end

  def fence_meeting(owner, due_at)
    connection = ActiveRecord::Base.connection
    key = connection.quote("jrc-domain-meeting:#{@account.id}:#{owner.id}:#{due_at.utc.iso8601(6)}")
    connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{key},0))")
    return unless @account.jrc_crm_activities.exists?(user: owner, activity_type: 'meeting', status: 'scheduled', due_at: due_at)

    raise ArgumentError, 'domain_meeting_conflict'
  end
end
