# frozen_string_literal: true

# Explicit projection; never ActiveRecord#as_json of a ticket/snapshot/blob.
class JrcServiceDesk::Presenter
  EVENT_FIELDS = {
    'operational_rule_applied' => %w[kind rule_version_id rule_key rule_digest snapshot_id],
    'clock_threshold_reached' => %w[clock_id clock_kind percent policy_digest elapsed_seconds budget_seconds due_at breached target_queue_id],
    'clock_violated' => %w[clock_id clock_kind policy_digest elapsed_seconds budget_seconds due_at observed_at],
    'approval_escalated' => %w[approval_id history_index],
    'resource_linked' => %w[resource_id resource_kind], 'resource_updated' => %w[resource_id resource_kind history_index],
    'resource_archived' => %w[resource_id resource_kind history_index],
    'ticket_created' => %w[status_id priority_id queue_id assignee_membership_id],
    'ticket_updated' => %w[title description priority_id category_id status_id company_id],
    'ticket_assigned' => %w[assignee_membership_id queue_id team_id],
    'ticket_transferred' => %w[assignee_membership_id queue_id team_id],
    'note_added' => %w[note_id notification_state], 'interaction_republished' => %w[note_id previous_note_id notification_state],
    'task_created' => %w[task_id status], 'task_updated' => %w[task_id changes],
    'approval_requested' => %w[approval_id], 'approval_decided' => %w[approval_id changes],
    'incident_linked' => %w[incident_id primary_ticket_id], 'incident_updated' => %w[incident_id changes],
    'ticket_claimed' => %w[assignee_membership_id], 'notification_delivery_updated' => %w[note_id delivery_id channel state],
    'notification_resend_requested' => %w[original_delivery_id delivery_id reason],
    'ticket_auto_routed' => %w[assignee_membership_id queue_id mode],
    'first_response_recorded' => %w[message_id conversation_id clock_id cycle_id achieved_at snapshot_id],
    'conversation_linked' => %w[conversation_id link_id],
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
                         impact_code: record.impact_code, urgency_code: record.urgency_code,
                         service: named(record.service), status: named(record.status), priority: named(record.priority),
                         category: named(record.category), ticket_type: named(record.ticket_type), subcategory: named(record.subcategory),
                         **catalogue_fields(record, policy),
                         requester: policy.view_customer? ? native_named(requester) : nil,
                         **master_company_fields(record, policy),
                         assignee: assignee(record.assignee_membership),
                         team: native_named(team),
                         queue: named(record.queue), source: record.origin_channel, lock_version: record.lock_version,
                         sla: policy.view_sla? ? sla_summary(record) : nil,
                         permissions: JrcServiceDesk::TicketPermissions.new(@context, record, policy).call)
  end

  def catalog(record, resource:, unit_id: nil)
    if resource == 'contracts'
      context = JrcServiceDesk::OperationalContext.new(@context)
      JrcServiceDesk::CatalogueContracts.new(context).scope.find(record.id)
      { id: record.id.to_s, account_id: record.account_id.to_s, unit_id: unit_id.to_s, name: record.contract_number,
        contact_id: record.contact_id&.to_s, company_id: JrcServiceDesk::CatalogueContracts.company_id(record)&.to_s,
        permissions: { show: true } }
    elsif resource == 'assignees'
      { id: record.account_user_id.to_s, account_user_id: record.account_user_id.to_s,
        membership_id: record.id.to_s,
        account_id: record.account_id.to_s, unit_id: record.unit_id.to_s,
        name: record.account_user.user.name.to_s, active: record.active, permissions: { show: true } }
    elsif %w[requesters teams].include?(resource)
      raise Pundit::NotAuthorizedError unless JrcServiceDesk::OperationalContext.new(@context).record_in_account?(record) &&
                                              Pundit.policy!(@context, record).show?

      { id: record.id.to_s, account_id: record.account_id.to_s, unit_id: unit_id.to_s,
        name: record.name.to_s, permissions: { show: true } }
    else
      Pundit.authorize(@context, record, :show?)
      row = common(record).merge(name: record.name, code: record.code, active: record.active,
                                 permissions: { show: true, create: false, update: false })
      row[:operator_company_id] = record.operator_company_id.to_s if resource == 'units'
      row[:team] = native_named(record.team) if resource == 'queues'
      row[:position] = record.position if %w[statuses priorities].include?(resource)
      status_fields(row, record) if resource == 'statuses'
      row[:form_fields] = record.form_fields if %w[categories ticket_types].include?(resource)
      row[:parent_id] = record.parent_id&.to_s if resource == 'categories'

      row
    end
  end

  def related(record, kind)
    Pundit.authorize(@context, record, :show?)
    case kind
    when 'notes' then note_fields(record)
    when 'events' then event_fields(record)
    when 'sla' then JrcServiceDesk::SlaMilestoneProjection.new(record).call
    when 'conversations' then conversation_fields(record)
    when 'status_options' then catalog(record, resource: 'statuses')
    end
  end

  private

  def catalogue_fields(record, policy)
    return {} unless policy.view_customer?

    context = JrcServiceDesk::OperationalContext.new(@context)
    contract = JrcServiceDesk::CatalogueContracts.new(context).scope.find_by(id: record.contract_id) if record.contract_id
    result = { service_fields: record.service_fields, catalogue_form_fields: record.catalogue_snapshot.fetch('form_fields', []) }
    result[:contract] = contract && { id: contract.id.to_s, name: contract.contract_number } if contract || record.contract_id.nil?
    result
  end

  def status_fields(row, record)
    row[:phase] = record.phase
    row[:initial] = record.initial
  end

  def note_fields(record)
    common(record).merge(ticket_id: record.ticket_id.to_s, body: record.body, visibility: record.visibility,
                         audience_team_id: record.audience_team_id&.to_s, previous_note_id: record.previous_note_id&.to_s,
                         notification_state: record.notification_state, deliveries: note_deliveries(record),
                         attachments: note_attachments(record), author: assignee(record.author_membership))
  end

  def note_attachments(record)
    record.files.map do |file|
      { id: file.id.to_s, filename: file.filename.to_s, byte_size: file.blob.byte_size,
        scan_state: file.blob.metadata['service_desk_scan_state'] || 'unavailable' }
    end
  end

  def event_fields(record)
    common(record).merge(ticket_id: record.ticket_id.to_s, event_type: record.event_type,
                         data: event_data(record), author: assignee(record.actor_membership))
  end

  def conversation_fields(record)
    common(record).merge(ticket_id: record.ticket_id.to_s, conversation_id: record.conversation_id.to_s,
                         conversation_display_id: record.conversation.display_id.to_s)
  end

  def common(record)
    row = { id: record.id.to_s, account_id: record.account_id.to_s,
            created_at: stamp(record.created_at), permissions: { show: true } }
    row[:updated_at] = stamp(record.updated_at) if record.respond_to?(:updated_at)
    row[:unit_id] = record.unit_id.to_s if record.respond_to?(:unit_id)
    row
  end

  def master_company_fields(record, policy)
    return {} unless record.account.feature_enabled?('jrc_customer_master')

    allowed = policy.view_customer? && JrcCustomers::DirectoryPolicy.new(@context, :directory).access?
    company = JrcCustomers::Company.where(account_id: record.account_id).find_by(id: record.company_id) if allowed
    { company: company && named(company) }
  end

  def native_named(record)
    context = JrcServiceDesk::OperationalContext.new(@context)
    record && context.record_in_account?(record) && Pundit.policy!(context.to_h, record).show? ? named(record) : nil
  end

  def note_deliveries(record)
    context = JrcServiceDesk::OperationalContext.new(@context)
    JrcServiceDesk::NotificationDelivery.where(account_id: record.account_id, unit_id: record.unit_id,
                                               ticket_id: record.ticket_id, ticket_note_id: record.id).order(:id).filter_map do |row|
      { channel: row.channel, state: row.state, reason: row.reason } if JrcServiceDesk::DeliveryAccess.new(context).allowed?(row)
    end
  end

  def event_data(record)
    JrcServiceDesk::EventDataProjection.new(@context).call(record)
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
      attendance = clocks.find { |clock| clock.kind == 'attendance' }
      state = clocks.any? { |clock| clock.state == 'paused' } ? 'paused' : 'calculated'
      return { state: state, first_response_due_at: stamp(first&.due_at), resolution_due_at: stamp(resolution&.due_at),
               attendance_due_at: stamp(attendance&.due_at), clocks: clocks.map { |clock| JrcServiceDesk::ClockProjection.new(clock).call } }
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
