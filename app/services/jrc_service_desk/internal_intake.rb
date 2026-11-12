# frozen_string_literal: true

# Internal requests use the authenticated employee, never a caller-supplied identity.
# Routing is configured per account/unit and uses the existing shared team scope.
class JrcServiceDesk::InternalIntake
  KEY = 'jrc_service_desk_internal_intake'

  def self.configuration(unit)
    unit.account.internal_attributes.fetch(KEY, {})[unit.id.to_s]
  end

  def self.presentation(unit, context)
    return unless configuration(unit)

    queue, primary, observer = destinations(unit)
    { requester: { name: context.user.name, email: context.user.email },
      primary: { id: primary.account_user_id.to_s, name: primary.account_user.user.name },
      observer: { id: observer.account_user_id.to_s, name: observer.account_user.user.name },
      queue: { id: queue.id.to_s, name: queue.name } }
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
    if JrcServiceDesk::EmployeeAccess.restricted?(context) && contact.company_id.present?
      allowed = JrcServiceDesk::EmployeeAccess.configurations(context).values.map { |row| row['internal_company_id'] }.compact
      raise Pundit::NotAuthorizedError unless allowed.include?(contact.company_id)
    end
    JrcServiceDesk::RequesterDirectory.new(context).validate!(contact)
    contact
  end

  def self.defaults!(unit, context)
    destinations(unit)
    requester = identity!(context)
    status = JrcServiceDesk::TicketStatus.where(account_id: unit.account_id, unit_id: unit.id).find_by!(active: true, initial: true, phase: 'open')
    priority = JrcServiceDesk::Priority.where(account_id: unit.account_id, unit_id: unit.id, active: true)
      .where('LOWER(code) = ? OR LOWER(name) = ?', 'normal', 'normal').sole
    { 'requester_id' => requester.id, 'status_id' => status.id, 'priority_id' => priority.id }
  end

  def self.apply!(ticket)
    queue, primary, = destinations(ticket.unit)
    ticket.queue = queue
    ticket.team_id = queue.team_id
    ticket.assignee_membership = primary
  end
end
