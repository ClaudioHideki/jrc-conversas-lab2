# Read-only projections of the same authorized sources used by Customer360.
# No message bodies, notes, metadata or private record snapshots enter this view.
class JrcCustomers::OperationalSources
  DEFAULTS = {
    contact_id: 'NULL::bigint', kind: "''::text", record_id: 'NULL::bigint', display_id: 'NULL::bigint',
    state: "''::text", occurred_at: 'NULL::timestamp', due_at: 'NULL::timestamp', actor_id: 'NULL::bigint',
    channel_type: "''::text", channel_name: "''::text", title: "''::text", priority: '9', pending: 'FALSE', living: 'FALSE'
  }.freeze

  def initialize(account:, actor:, membership:, contact_scope:)
    @account = account
    @contacts = contact_scope
    @visibility = JrcCustomers::Visibility.new(account: account, user: actor, account_user: membership)
  end

  def sql
    (conversation_sources + crm_sources + service_desk_sources + call_sources).map(&:to_sql).join(' UNION ALL ')
  end

  private

  def project(scope, values)
    fields = DEFAULTS.merge(values).map { |key, value| "#{value} AS #{key}" }.join(', ')
    scope.reorder(nil).reselect(Arel.sql(fields))
  end

  def conversations
    @conversations ||= @visibility.conversations.where(contact_id: @contacts.select(:id))
  end

  def conversation_values
    { contact_id: 'conversations.contact_id', kind: "'conversation'", record_id: 'conversations.id',
      display_id: 'conversations.display_id', actor_id: 'conversations.assignee_id',
      state: "CASE conversations.status WHEN 0 THEN 'open' WHEN 1 THEN 'resolved' ELSE 'waiting' END",
      channel_type: 'inboxes.channel_type', channel_name: 'inboxes.name' }
  end

  def conversation_sources
    active = project(conversations.where.not(status: :resolved).joins(:inbox),
                     conversation_values.merge(living: 'TRUE', priority: 'CASE WHEN conversations.status = 0 THEN 0 ELSE 1 END'))
    messages = Message.where(account_id: @account.id, conversation_id: conversations.select(:id), private: false, message_type: [0, 1])
                      .joins(conversation: :inbox)
    [active, project(messages, conversation_values.merge(occurred_at: 'messages.created_at', priority: '3'))]
  end

  def crm_sources
    activities = @visibility.crm(@account.jrc_crm_activities, owner: :user_id)
    values = { kind: "'activity'", record_id: 'jrc_crm_activities.id', state: 'jrc_crm_activities.status',
               occurred_at: 'jrc_crm_activities.completed_at', due_at: 'jrc_crm_activities.due_at',
               actor_id: 'jrc_crm_activities.user_id', title: 'jrc_crm_activities.title',
               channel_type: 'jrc_crm_activities.activity_type', priority: '2',
               pending: "jrc_crm_activities.completed_at IS NULL AND jrc_crm_activities.status = 'scheduled'" }
    direct = project(activities.where(contact_id: @contacts.select(:id)), values.merge(contact_id: 'jrc_crm_activities.contact_id'))
    [direct] + %i[lead deal].flat_map do |kind|
      origins = @visibility.crm(@account.public_send("jrc_crm_#{kind}s")).where(contact_id: @contacts.select(:id))
      legacy = activities.where('contact_id' => nil, "#{kind}_id" => origins.select(:id)).joins(kind)
      linked = project(legacy, values.merge(contact_id: "jrc_crm_#{kind}s.contact_id"))
      follow_ups = @visibility.crm(@account.jrc_crm_follow_ups, owner: :user_id).where("#{kind}_id" => origins.select(:id)).joins(kind)
      follow_up_values = { contact_id: "jrc_crm_#{kind}s.contact_id", kind: "'follow_up'", record_id: 'jrc_crm_follow_ups.id',
                           state: "CASE WHEN jrc_crm_follow_ups.is_completed THEN 'completed' ELSE 'scheduled' END",
                           occurred_at: 'jrc_crm_follow_ups.completed_at', due_at: 'jrc_crm_follow_ups.due_at',
                           actor_id: 'jrc_crm_follow_ups.user_id', title: 'jrc_crm_follow_ups.title',
                           pending: 'NOT jrc_crm_follow_ups.is_completed AND jrc_crm_follow_ups.completed_at IS NULL', priority: '2' }
      [linked, project(follow_ups, follow_up_values)]
    end
  end

  def service_desk_sources
    tickets = @visibility.tickets.where(requester_id: @contacts.select(:id)).joins(:status).left_joins(assignee_membership: :account_user)
    values = { contact_id: 'jrc_service_desk_tickets.requester_id', kind: "'ticket'", record_id: 'jrc_service_desk_tickets.id',
               title: 'jrc_service_desk_tickets.title', state: 'jrc_service_desk_ticket_statuses.phase', priority: '2',
               actor_id: 'account_users.user_id', channel_type: 'jrc_service_desk_tickets.origin_channel' }
    active = project(tickets.where(jrc_service_desk_ticket_statuses: { phase: %w[open waiting] }), values.merge(living: 'TRUE'))
    events = @visibility.ticket_events(tickets).where(event_type: %w[ticket_created ticket_updated lifecycle_transitioned])
                        .joins(ticket: :status).left_joins(ticket: { assignee_membership: :account_user })
    [active, project(events, values.merge(occurred_at: 'jrc_service_desk_ticket_events.created_at', priority: '5'))]
  end

  def call_sources
    calls = @visibility.calls(contact_ids: @contacts.select(:id), conversation_ids: conversations.select(:id))
    return [] unless calls

    [project(calls, contact_id: 'calls.contact_id', kind: "'call'", record_id: 'calls.id', occurred_at: 'calls.started_at',
                    actor_id: 'calls.accepted_by_agent_id', channel_type: "'phone'", priority: '4',
                    state: "CASE WHEN calls.status IN ('ringing', 'in_progress') THEN 'open' ELSE 'resolved' END",
                    living: "calls.status IN ('ringing', 'in_progress')")]
  end
end
