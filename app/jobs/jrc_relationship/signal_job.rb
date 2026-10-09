class JrcRelationship::SignalJob < ApplicationJob
  queue_as :low
  SOURCES = %w[JrcCrm::SalesOrder JrcCrm::BackofficeRequest JrcCrm::Contract JrcCrm::Invoice
               JrcCrm::Activity JrcServiceDesk::Ticket JrcProjects::Project CsatSurveyResponse JrcRelationship::Survey].freeze

  def perform(type, id)
    raise ArgumentError, 'Invalid relationship event source' unless SOURCES.include?(type)

    record = type.constantize.find_by(id: id)
    return unless record && record.account.feature_enabled?('jrc_relationship')

    process_native_event(type, record)
    contact = record.try(:contact) || record.try(:requester) || record.try(:sales_order)&.contact
    return unless contact || type == 'JrcRelationship::Survey'

    scope = JrcRelationship::Assignment.where(account: record.account)
    scope = if type == 'JrcRelationship::Survey'
              scope.where(id: record.assignment_id)
            else
              contact.company_id ? scope.where(company_id: contact.company_id) : scope.where(contact_id: contact.id)
            end
    scope.find_each do |assignment|
      member = record.account.account_users.find_by(user_id: assignment.owner_id)
      next unless member && JrcRelationship::ModulePolicy.new({ account: record.account, user: member.user, account_user: member },
                                                              record.account).access?

      context = JrcRelationship::Context.new(member)
      next unless context.assignments.exists?(id: assignment.id)

      open_cancellation!(record, assignment, context) if context.policy.manage? && cancellation?(type, record)
      processor = JrcRelationship::Processor.new(context: context, assignment: assignment)
      data = processor.call
      follow_up_ticket!(record, assignment, context, processor, data) if critical_ticket?(type, record, assignment, context)
    end
  end

  private

  def process_native_event(type, record)
    if completed_attendance?(type, record)
      JrcRelationship::SurveyEngine.evaluate_closure(source: record, cycle_key: "crm-activity:#{record.id}:attendance")
    end
    JrcRelationship::Handoff.call(record) if handoff_ready?(type, record)
  end

  def completed_attendance?(type, record)
    type == 'JrcCrm::Activity' && record.status == 'completed' && JrcRelationship::ManualAttendance.eligible?(record)
  end

  def handoff_ready?(type, record)
    case type
    when 'JrcCrm::SalesOrder' then record.completed?
    when 'JrcProjects::Project' then record.status == 'completed'
    when 'JrcCrm::BackofficeRequest' then record.stage == 'completed' && record.status == 'completed' && !record.cancellation?
    else false
    end
  end

  def cancellation?(type, record)
    (type == 'JrcCrm::SalesOrder' && record.canceled?) || (type == 'JrcCrm::BackofficeRequest' && record.cancellation?)
  end

  def open_cancellation!(record, assignment, context)
    assignment.with_lock do
      risk = JrcRelationship::RiskCase.find_or_initialize_by(assignment: assignment, source_key: "cancellation:#{record.class.name}:#{record.id}")
      next if risk.persisted?

      risk.assign_attributes(account: record.account, owner: assignment.owner, kind: 'cancellation', severity: 'critical',
                             reason: 'Solicitação de cancelamento', due_at: Time.current)
      JrcRelationship::RiskFinancialSnapshot.capture!(risk, context)
      risk.save!
      context.audit!(risk, action: 'cancellation_retention_opened')
      JrcRelationship::Workflow.new(context).project_risk!(risk)
      JrcRelationship::Playbooks.new(context).run!(assignment, 'cancellation', source_key: risk.id)
    end
  end

  def critical_ticket?(type, record, assignment, context)
    return false unless context.policy.manage? && type == 'JrcServiceDesk::Ticket' && %w[resolved closed].include?(record.status.phase)

    context.configuration(assignment).effective_rules['critical_priority_codes'].include?(record.priority.code) &&
      assignment.customer_context(context.member).tickets.exists?(id: record.id)
  end

  def follow_up_ticket!(record, assignment, context, processor, data)
    assignment.with_lock do
      action = processor.action!('post_ticket', "Follow-up após chamado crítico #{record.id}", data,
                                 context.configuration(assignment).effective_rules, key: "post-ticket:#{record.id}")
      JrcRelationship::Playbooks.new(context).run!(assignment, 'ticket', source_key: action.id)
    end
  end
end
