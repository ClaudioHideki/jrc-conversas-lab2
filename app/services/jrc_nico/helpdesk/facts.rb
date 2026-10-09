class JrcNico::Helpdesk::Facts
  def initialize(context:, policy:, ticket:, trigger:, now: Time.current)
    @context = context
    @policy = policy
    @ticket = ticket
    @trigger = trigger
    @now = now
  end

  def call
    profile = JrcNico::Helpdesk::TicketProfile.find_by(account: @context.account, ticket: @ticket)
    phase = @ticket.status.phase
    data = { 'ticket_id' => @ticket.id, 'company_id' => @ticket.company_id, 'unit_id' => @ticket.unit_id,
             'case_kind' => profile&.case_kind, 'defect_key' => profile&.defect_key, 'service_id' => @ticket.service_id,
             'ticket_type_id' => @ticket.ticket_type_id,
             'priority_id' => @ticket.priority_id, 'phase' => phase, 'open' => %w[closed cancelled].exclude?(phase),
             'waiting_for_approval' => @ticket.ticket_approvals.exists?(status: 'pending'),
             'trigger' => @trigger, 'cycle_key' => cycle_key, 'occurred_at' => @now.iso8601(6) }
    related!(data, profile)
    clock!(data)
    interaction!(data, profile)
    survey!(data)
    data
  end

  private

  def cycle_key
    return unless @context.native.capability?(:history_view)

    JrcNico::Helpdesk::CycleEvidence.key(@ticket)
  end

  def related!(data, profile)
    return unless profile&.defect_key && @ticket.company_id

    profiles = related_profiles(profile)
    data['occurrences'] = profiles.map { |item| occurrence(item) }
    data['previous_cases'] = profiles.reject { |item| item.ticket_id == @ticket.id }.map { |item| previous_case(item) }
  end

  def related_profiles(profile)
    scope = @context.tickets.where(unit_id: @ticket.unit_id, company_id: @policy.definition.fetch('company_ids'))
    JrcNico::Helpdesk::TicketProfile.where(account: @context.account, ticket_id: scope.select(:id),
                                           defect_key: profile.defect_key, case_kind: 'defect').includes(ticket: :status)
  end

  def occurrence(item)
    { 'id' => item.ticket_id, 'company_id' => item.company_id, 'defect_key' => item.defect_key, 'age_seconds' => @now - item.ticket.opened_at }
  end

  def previous_case(item)
    closed_at = item.ticket.lifecycle_transitions.where(action: 'close').maximum(:occurred_at) if @context.native.capability?(:history_view)
    { 'id' => item.ticket_id, 'company_id' => item.company_id, 'defect_key' => item.defect_key,
      'open' => %w[closed cancelled].exclude?(item.ticket.status.phase), 'closed_age_seconds' => closed_at && (@now - closed_at) }
  end

  def clock!(data)
    return unless @context.native.capability?(:sla_view)

    cycle = @ticket.sla_cycles.order(number: :desc).first
    clock = cycle&.sla_clocks&.find_by(kind: 'resolution')
    return unless clock

    calendar = JrcServiceDesk::LifecycleClocks.verify_snapshot!(cycle.sla_snapshot)
    elapsed = clock.elapsed_seconds.to_f
    elapsed += calendar.elapsed(clock.anchor_at, @now) if clock.state == 'running'
    clock_data!(data, clock, calendar, elapsed)
  end

  def clock_data!(data, clock, calendar, elapsed)
    data.merge!('clock_id' => clock.id, 'sla_running' => clock.state == 'running', 'sla_budget_seconds' => clock.budget_seconds,
                'sla_elapsed_seconds' => elapsed, 'due_at' => clock.due_at.iso8601(6),
                'overdue_calendar_seconds' => [@now - clock.due_at, 0].max,
                'overdue_business_seconds' => @now > clock.due_at ? calendar.elapsed(clock.due_at, @now) : 0)
  end

  def interaction!(data, profile)
    # Only explicit customer-origin evidence is inspected, never internal operator text or inferred authorship.
    scope = JrcServiceDesk::TicketNotePolicy::Scope.new(@context.native.to_h, JrcServiceDesk::TicketNote).resolve.where(ticket_id: @ticket.id)
    notes = customer_notes(profile, scope)
    data['customer_note_ids'] = notes.map(&:id)
    data['customer_text'] = notes.map(&:body).join("\n").truncate(50_000)
    activity!(data, profile, scope)
    negative_return!(data, profile)
    data['source_occurred_at'] = notes.map(&:created_at).max&.iso8601(6) || @ticket.opened_at.iso8601(6)
  end

  def customer_notes(profile, scope)
    note_ids = Array(profile&.evidence&.fetch('customer_note_ids', []))
    scope.where(id: note_ids).to_a
  end

  def negative_return!(data, profile)
    data['negative_return'] = JrcNico::Helpdesk::CycleEvidence.valid_negative?(ticket: @ticket, profile: profile,
                                                                               cycle_key: data['cycle_key'], context: @context, now: @now)
    data.merge!(profile.evidence.slice(*JrcNico::Helpdesk::CycleEvidence::FIELDS)) if data['negative_return']
  end

  def activity!(data, profile, scope)
    unless @context.native.capability?(:history_view)
      data['activity_coverage'] = 'history_permission_required'
      return
    end

    human_notes = scope.includes(author_membership: :account_user).select do |note|
      human_record?(note, :author_membership)
    end.map(&:created_at).max
    relevant = [profile&.last_relevant_at, human_notes, human_task_activity, human_task_update_activity, human_transition_activity,
                human_update_activity, @ticket.opened_at].compact.max
    data['activity_coverage'] = 'authorized_native_history'
    data['last_relevant_at'] = relevant.iso8601(6)
    data['inactive_seconds'] = [@now - relevant, 0].max
  end

  def human_task_activity
    return unless @context.native.capability?(:tasks_view)

    rows = JrcServiceDesk::TicketTaskPolicy::Scope.new(@context.native.to_h, JrcServiceDesk::TicketTask).resolve.where(ticket_id: @ticket.id)
    rows.includes(created_by_membership: :account_user).select { |task| human_record?(task, :created_by_membership) }
        .map(&:updated_at).max
  end

  def human_transition_activity
    return unless @context.native.capability?(:history_view)

    @ticket.lifecycle_transitions.includes(actor_membership: :account_user).select do |transition|
      human_record?(transition, :actor_membership)
    end.map(&:occurred_at).max
  end

  def human_task_update_activity
    return unless @context.native.capability?(:tasks_view)

    tasks = JrcServiceDesk::TicketTaskPolicy::Scope.new(@context.native.to_h, JrcServiceDesk::TicketTask).resolve.where(ticket_id: @ticket.id)
    scope = JrcServiceDesk::TicketEventPolicy::Scope.new(@context.native.to_h, JrcServiceDesk::TicketEvent).resolve
    scope.where(ticket_id: @ticket.id, event_type: 'task_updated').select do |event|
      human_task_update?(event, tasks)
    end.map(&:created_at).max
  end

  def human_task_update?(event, tasks)
    tasks.exists?(id: event.data['task_id']) && changed_pairs?(event.data.fetch('changes', {})) &&
      !JrcNico::Helpdesk::NativeOrigin.new(event).proven_nico?
  end

  def human_record?(row, actor_field)
    # Field names are fixed server-side callers. A customer-supplied prefix is never origin proof.
    actor = row.public_send(actor_field)&.account_user
    return false unless actor&.account_id == @context.account.id

    !JrcNico::Helpdesk::NativeOrigin.new(row).proven_nico?
  end

  def human_update_activity
    scope = JrcServiceDesk::TicketEventPolicy::Scope.new(@context.native.to_h, JrcServiceDesk::TicketEvent).resolve
    scope.where(ticket_id: @ticket.id, event_type: 'ticket_updated').select do |event|
      changed = changed_pairs?(event.data.except('origin', 'notification_fields'))
      changed && !JrcNico::Helpdesk::NativeOrigin.new(event).proven_nico?
    end.map(&:created_at).max
  end

  def changed_pairs?(changes)
    changes.values.any? { |pair| pair.is_a?(Array) && pair.size == 2 && pair.first != pair.last }
  end

  def survey!(data)
    # Native close calls the same engine/cycle. Reading the decision does not send or schedule a second survey.
    return unless defined?(JrcRelationship::SurveyDispatchDecision)

    decision = JrcRelationship::SurveyDispatchDecision.where(account_id: @ticket.account_id, source_type: @ticket.class.name,
                                                             source_id: @ticket.id, cycle_key: data['cycle_key']).order(:id).last
    if decision
      evidence = { 'survey_decision_id' => decision.id, 'survey_id' => decision.survey_id, 'cycle_key' => data['cycle_key'] }.compact
      JrcNico::Helpdesk::EvidenceAccess.new(@context, @ticket, evidence).call
      data['survey_decision_id'] = decision.id
    end
    return unless decision&.survey_id

    survey = JrcNico::DomainAccess.authorize_resource!(@context.access, 'JrcRelationship::Survey', decision.survey_id)
    survey_data!(data, survey)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    nil
  end

  def survey_data!(data, survey)
    # The immutable definition's principal question can have any key (e.g. rating).
    question = survey.questions.first
    scale = question && question['type'] == 'scale' ? "#{question['min']}-#{question['max']}" : nil
    data.merge!('survey_id' => survey.id, 'survey_model' => survey.kind, 'survey_score' => survey.score,
                'survey_scale' => scale,
                'survey_recovery_id' => survey.metadata['recovery_risk_id'])
  end
end
