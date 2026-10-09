class JrcRelationship::SurveyLinks
  def initialize(context, survey)
    @context = context
    @survey = survey
  end

  def call
    links = []
    source_link = origin_link
    links << source_link if source_link
    if @survey.assignment_id && @context.assignments.exists?(id: @survey.assignment_id)
      links << link('customer', @survey.assignment_id, 'jrc_relationship_health', query: { customer: @survey.assignment_id })
      { 'risk' => [JrcRelationship::RiskCase, 'recovery_risk_id', 'jrc_relationship_risks'],
        'action' => [JrcRelationship::Action, 'recovery_action_id', 'jrc_relationship_actions'] }.each do |kind, (model, key, route)|
        id = @survey.metadata[key]
        next unless id && @context.records(model).where(assignment_id: @survey.assignment_id).exists?(id: id)

        links << link(kind, id, route, query: { assignment_id: @survey.assignment_id, record_id: id })
      end
    end
    links
  end

  private

  def origin_link
    visibility = JrcCustomers::Visibility.new(account: @context.account, user: @context.user, account_user: @context.member)
    id = @survey.source_id
    case @survey.source_type
    when 'Conversation' then conversation_link(visibility, id)
    when 'JrcServiceDesk::Ticket'
      link('ticket', id, 'jrc_service_desk_detail', params: { ticketId: id }) if visibility.tickets.exists?(id: id)
    when 'JrcRelationship::Qbr' then qbr_link(id)
    when 'JrcCrm::Activity' then activity_link(visibility, id)
    when 'Call' then call_link(visibility, id)
    end
  end

  def conversation_link(visibility, id)
    conversation = visibility.conversations.find_by(id: id)
    link('conversation', id, 'inbox_conversation', params: { conversation_id: conversation.display_id }) if conversation
  end

  def qbr_link(id)
    return unless @context.records(JrcRelationship::Qbr).exists?(id: id)

    link('qbr', id, 'jrc_relationship_qbrs', query: { assignment_id: @survey.assignment_id, record_id: id })
  end

  def activity_link(visibility, id)
    return unless visibility.crm(@context.account.jrc_crm_activities, owner: :user_id).exists?(id: id)

    link('activity', id, 'crm_activities', query: { activityId: id })
  end

  def call_link(visibility, id)
    calls = visibility.calls(contact_ids: @context.account.contacts.select(:id), conversation_ids: visibility.conversations.select(:id))
    call = calls&.find_by(id: id)
    return unless call&.conversation_id && visibility.conversations.exists?(id: call.conversation_id)

    link('call', id, 'inbox_conversation', params: { conversation_id: call.conversation.display_id })
  end

  def link(kind, id, name, params: {}, query: {})
    { kind: kind, id: id, route: { name: name, params: params.merge(accountId: @context.account.id), query: query } }
  end
end
