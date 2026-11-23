# frozen_string_literal: true

# Internal requests use the authenticated employee, never a caller-supplied identity.
# Explicit recipients use their own unit/team domain; legacy defaults remain
# available for callers that do not select a recipient.
class JrcServiceDesk::InternalIntake
  KEY = 'jrc_service_desk_internal_intake'

  def self.configuration(unit)
    unit.account.internal_attributes.fetch(KEY, {})[unit.id.to_s]
  end

  def self.presentation(unit, context)
    values = configuration(unit) || {}
    queue = default_queue(unit)
    members = assignees(unit, queue)
    primary = members.find { |member| member.account_user_id.to_s == values['assignee_account_user_id'].to_s }
    observer = members.find { |member| member.account_user_id.to_s == values['observer_account_user_id'].to_s }
    { requester: { name: context.user.name, email: context.user.email },
      primary: primary && { id: primary.account_user_id.to_s, name: primary.account_user.user.name },
      observer: observer && { id: observer.account_user_id.to_s, name: observer.account_user.user.name },
      queue: queue && { id: queue.id.to_s, name: queue.name },
      assignees: members.map { |member| { id: member.account_user_id.to_s, name: member.account_user.user.name } } }
  end

  def self.assignees(unit, queue)
    JrcServiceDesk::UnitMembership.operational.where(account_id: unit.account_id, unit_id: unit.id, active: true,
                                                    manual_assignment_enabled: true).includes(:queue, :team, account_user: :user)
      .select { |member| recipient_allowed?(member, destination(unit, member, queue)) }
      .sort_by { |member| [member.account_user.user.name.downcase, member.account_user_id] }
  end

  def self.default_queue(unit)
    values = configuration(unit) || {}
    JrcServiceDesk::Queue.find_by(account_id: unit.account_id, unit_id: unit.id, active: true, id: values['queue_id'])
  end

  def self.destination(unit, member, queue)
    candidate = JrcServiceDesk::Ticket.new(account: unit.account, unit: unit, queue: queue, team_id: queue&.team_id)
    return candidate if recipient_allowed?(member, candidate)

    JrcServiceDesk::Ticket.new(account: unit.account, unit: unit, queue: member.queue, team: member.queue&.team || member.team)
  end

  def self.recipient_allowed?(member, ticket)
    member.account_user.user.reload.active_for_authentication? &&
      (!ticket.queue || ticket.queue.active?) && JrcServiceDesk::AssignmentEligibility.manual_domain?(member, ticket)
  end

  def self.destinations(unit)
    values = configuration(unit) || raise(ArgumentError, 'Internal intake is not configured')
    queue = JrcServiceDesk::Queue.where(account_id: unit.account_id, unit_id: unit.id, active: true).find(JrcServiceDesk::Input.id(values.fetch('queue_id')))
    raise ArgumentError, 'Internal intake requires a shared team' unless queue.team_id

    members = %w[assignee_account_user_id observer_account_user_id].map do |key|
      member = JrcServiceDesk::UnitMembership.operational.where(account_id: unit.account_id, unit_id: unit.id, active: true)
        .find_by!(account_user_id: JrcServiceDesk::Input.id(values.fetch(key)))
      target = JrcServiceDesk::OperationalContext.new(account: unit.account, user: member.account_user.user, account_user: member.account_user)
      candidate = JrcServiceDesk::Ticket.new(account: unit.account, unit: unit, queue: queue, team_id: queue.team_id)
      unless target.capability?(:tickets_view) && target.unit_allowed?(unit) && target.supervision_access.allowed?(candidate, 'tickets_view')
        raise Pundit::NotAuthorizedError
      end
      TeamMember.where(team_id: queue.team_id, user_id: member.account_user.user_id).take!
      member
    end
    primary, observer = members
    candidate = JrcServiceDesk::Ticket.new(account: unit.account, unit: unit, queue: queue, team_id: queue.team_id)
    raise Pundit::NotAuthorizedError unless JrcServiceDesk::AssignmentEligibility.manual_domain?(primary, candidate)

    [queue, primary, observer]
  end

  def self.identity!(context)
    contact = context.account.contacts.where('LOWER(email) = ?', context.user.email.downcase).first
    contact ||= context.account.contacts.create!(name: context.user.name, email: context.user.email,
                                                identifier: "internal-user:#{context.user.id}", additional_attributes: { entity_type: 'person' })
    validate_identity!(context, contact)
    contact
  end

  def self.validate_identity!(context, contact)
    unless contact.account_id == context.account.id && contact.email.to_s.casecmp?(context.user.email)
      raise Pundit::NotAuthorizedError
    end
    if JrcServiceDesk::EmployeeAccess.restricted?(context) && contact.company_id.present?
      allowed = JrcServiceDesk::EmployeeAccess.configurations(context).values.map { |row| row['internal_company_id'] }.compact
      raise Pundit::NotAuthorizedError unless allowed.include?(contact.company_id)
    end
    reason = JrcCustomers::RequesterIdentity.reason(contact)
    if reason
      raise JrcServiceDesk::RequestValidationError, reason == 'organization' ? 'requester_is_company' : 'requester_review_required'
    end
  end

  def self.defaults!(unit, context, assignee_account_user_id: nil)
    destinations(unit) unless assignee_account_user_id
    requester = identity!(context)
    status = JrcServiceDesk::TicketStatus.where(account_id: unit.account_id, unit_id: unit.id).find_by!(active: true, initial: true, phase: 'open')
    priority = JrcServiceDesk::Priority.where(account_id: unit.account_id, unit_id: unit.id, active: true)
      .where('LOWER(code) = ? OR LOWER(name) = ?', 'normal', 'normal').sole
    { 'requester_id' => requester.id, 'status_id' => status.id, 'priority_id' => priority.id }
  end

  def self.apply!(ticket, account_user_id: nil)
    if account_user_id
      selected = JrcServiceDesk::UnitMembership.operational.where(account_id: ticket.account_id,
        unit_id: ticket.unit_id, active: true).find_by!(account_user_id: account_user_id)
      target = destination(ticket.unit, selected, default_queue(ticket.unit))
      ticket.queue = target.queue
      ticket.team = target.team
    else
      queue, selected, = destinations(ticket.unit)
      ticket.queue = queue
      ticket.team_id = queue.team_id
    end
    raise Pundit::NotAuthorizedError unless recipient_allowed?(selected, ticket)

    ticket.assignee_membership = selected
  end

  def self.observer_for(ticket)
    id = configuration(ticket.unit)&.fetch('observer_account_user_id', nil)
    return unless id

    member = JrcServiceDesk::UnitMembership.operational.find_by(account_id: ticket.account_id, unit_id: ticket.unit_id,
      active: true, account_user_id: id)
    return unless member

    target = JrcServiceDesk::OperationalContext.new(account: ticket.account, user: member.account_user.user, account_user: member.account_user)
    member if Pundit.policy!(target.to_h, ticket).show?
  end
end
