# frozen_string_literal: true

# Explicit projection; never ActiveRecord#as_json of a ticket/snapshot/blob.
class JrcServiceDesk::Presenter
  EVENT_FIELDS = {
    'ticket_created' => %w[status_id priority_id queue_id assignee_membership_id],
    'ticket_updated' => %w[title description priority_id category_id status_id],
    'ticket_assigned' => %w[assignee_membership_id queue_id team_id],
    'ticket_transferred' => %w[assignee_membership_id queue_id team_id],
    'note_added' => %w[note_id], 'conversation_linked' => %w[conversation_id link_id],
    'sla_snapshot_recorded' => %w[snapshot_id version], 'creation_context_recorded' => [],
    'lifecycle_policy_bound' => %w[policy_version_id version digest],
    'lifecycle_transitioned' => %w[transition_id action from_status_id to_status_id policy_version_id policy_version cycle_id]
  }.freeze
  def initialize(user_context:)
    @context = user_context
  end

  def ticket(record)
    policy = Pundit.policy!(@context, record)
    raise Pundit::NotAuthorizedError unless policy.show?
    requester = record.requester
    team = record.team
    common(record).merge(title: record.title, number: record.id.to_s, description: record.description,
      service: named(record.service), status: named(record.status), priority: named(record.priority), category: named(record.category),
      requester: policy.view_customer? ? native_named(requester) : nil,
      assignee: assignee(record.assignee_membership),
      team: native_named(team),
      queue: named(record.queue), source: record.origin_channel, lock_version: record.lock_version,
      sla: policy.view_sla? ? sla_summary(record) : nil,
      permissions: { show: true, update: policy.update?, change_priority: policy.change_priority?, assign: policy.assign?, transfer: policy.transfer?,
                     view_notes: policy.view_notes?, view_history: policy.view_history?, view_conversations: policy.view_conversations?,
                     view_sla: policy.view_sla?, view_customer: policy.view_customer?,
                     lifecycle_inspect: JrcServiceDesk::LifecycleActionPolicy.new(@context, record).inspect?, add_note: policy.add_note?,
                     link_conversation: policy.link_conversation?,
                     change_work_status: JrcServiceDesk::WorkStatusPolicy.new(@context, record).change_work_status?,
                     transition: false, pause: false, resolve: false, reopen: false })
  end

  def catalog(record, resource:, unit_id: nil)
    if resource == 'assignees'
      { id: record.account_user_id.to_s, account_user_id: record.account_user_id.to_s,
        account_id: record.account_id.to_s, unit_id: record.unit_id.to_s,
        name: record.account_user.user.name.to_s, active: record.active, permissions: { show: true } }
    elsif %w[requesters teams].include?(resource)
      raise Pundit::NotAuthorizedError unless JrcServiceDesk::OperationalContext.new(@context).record_in_account?(record) && Pundit.policy!(@context, record).show?
      { id: record.id.to_s, account_id: record.account_id.to_s, unit_id: unit_id.to_s,
        name: record.name.to_s, permissions: { show: true } }
    else
      Pundit.authorize(@context, record, :show?)
      row = common(record).merge(name: record.name, code: record.code, active: record.active,
                                permissions: { show: true, create: false, update: false })
      row[:operator_company_id] = record.operator_company_id.to_s if resource == 'units'
      row[:team] = native_named(record.team) if resource == 'queues'
      row[:position] = record.position if %w[statuses priorities].include?(resource)
      if resource == 'statuses'
        row[:phase] = record.phase
        row[:initial] = record.initial
      end
      row
    end
  end

  def related(record, kind)
    Pundit.authorize(@context, record, :show?)
    case kind
    when 'notes'
      common(record).merge(ticket_id: record.ticket_id.to_s, body: record.body, visibility: 'internal',
                           author: assignee(record.author_membership))
    when 'events'
      common(record).merge(ticket_id: record.ticket_id.to_s, event_type: record.event_type,
                           data: event_data(record),
                           author: assignee(record.actor_membership))
    when 'sla'
      { id: record.id.to_s, account_id: record.account_id.to_s, unit_id: record.unit_id.to_s,
        ticket_id: record.ticket_id.to_s, kind: record.kind, due_at: stamp(record.due_at), achieved_at: stamp(record.achieved_at),
        calculated_at: stamp(record.calculated_at), calculator_version: record.calculator_version,
        permissions: { show: true }, snapshot_version: record.sla_snapshot.version, met: record.met?, calculation_pending: record.calculation_pending? }
    when 'conversations'
      common(record).merge(ticket_id: record.ticket_id.to_s, conversation_id: record.conversation_id.to_s,
                           conversation_display_id: record.conversation.display_id.to_s)
    when 'status_options'
      catalog(record, resource: 'statuses')
    end
  end

  private

  def common(record)
    row = { id: record.id.to_s, account_id: record.account_id.to_s,
            created_at: stamp(record.created_at), permissions: { show: true } }
    row[:updated_at] = stamp(record.updated_at) if record.respond_to?(:updated_at)
    row[:unit_id] = record.unit_id.to_s if record.respond_to?(:unit_id)
    row
  end

  def native_named(record)
    context = JrcServiceDesk::OperationalContext.new(@context)
    record && context.record_in_account?(record) && Pundit.policy!(context.to_h, record).show? ? named(record) : nil
  end

  def event_data(record)
    data = record.data.slice(*EVENT_FIELDS.fetch(record.event_type, []))
    context = JrcServiceDesk::OperationalContext.new(@context)
    return {} if record.event_type == 'note_added' && !context.capability?(:notes_view)
    return {} if record.event_type == 'sla_snapshot_recorded' && !context.capability?(:sla_view)
    data.delete('cycle_id') if record.event_type == 'lifecycle_transitioned' && !context.capability?(:sla_view)
    if record.event_type == 'conversation_linked'
      context = JrcServiceDesk::OperationalContext.new(@context)
      return {} unless context.capability?(:conversations_view)
      conversation = Conversation.find_by(account_id: context.account.id, id: data['conversation_id'])
      return {} unless conversation && Pundit.policy!(context.to_h, conversation).show?
    end
    data
  end

  def named(record)
    record && { id: record.id.to_s, name: record.name.to_s }
  end

  def assignee(membership)
    return nil unless membership
    context = JrcServiceDesk::OperationalContext.new(@context)
    return nil unless context.record_in_account?(membership) && context.unit_scope.exists?(id: membership.unit_id)
    return nil unless membership.account_user.account_id == context.account.id

    { id: membership.account_user_id.to_s, name: membership.account_user.user.name.to_s }
  end

  def stamp(value)
    value&.iso8601(6)
  end

  def sla_summary(ticket)
    cycle = ticket.sla_cycles.order(number: :desc).first
    if cycle
      clocks = cycle.sla_clocks.to_a
      first = clocks.find { |clock| clock.kind == 'first_response' }
      resolution = clocks.find { |clock| clock.kind == 'resolution' }
      state = clocks.any? { |clock| clock.state == 'paused' } ? 'paused' : 'calculated'
      return { state: state, first_response_due_at: stamp(first&.due_at), resolution_due_at: stamp(resolution&.due_at) }
    end
    snapshot = ticket.latest_sla_snapshot
    return { state: 'unavailable', first_response_due_at: nil, resolution_due_at: nil } unless snapshot
    records = snapshot.sla_milestones.to_a
    first = records.find { |milestone| milestone.kind == 'first_response' }
    resolution = records.find { |milestone| milestone.kind == 'resolution' }
    { state: records.length == 2 && records.all? { |milestone| !milestone.calculation_pending? } ? 'calculated' : 'pending',
      first_response_due_at: stamp(first&.due_at), resolution_due_at: stamp(resolution&.due_at) }
  end
end
