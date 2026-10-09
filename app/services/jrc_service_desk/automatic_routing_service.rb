# frozen_string_literal: true

class JrcServiceDesk::AutomaticRoutingService < JrcServiceDesk::BaseService
  def call(ticket_id:)
    with_ticket(ticket_id, :assign?) do |ticket|
      queue = ticket.queue
      next ticket unless routable?(ticket, queue)

      ticket = priority_ticket(ticket, queue)
      next nil unless ticket

      chosen = choose(candidates(ticket, queue), queue.distribution_mode)
      next ticket unless chosen

      ticket.assignee_membership = assignee(chosen[:membership].account_user_id, ticket.unit)
      ticket.save!
      append_event!(ticket, 'ticket_auto_routed', 'assignee_membership_id' => ticket.assignee_membership_id,
                                                  'queue_id' => queue.id, 'mode' => queue.distribution_mode)
      ticket
    end
  end

  private

  def routable?(ticket, queue)
    queue&.active? && queue.distribution_mode != 'manual' && !ticket.assignee_membership_id && ticket.status.phase == 'open'
  end

  def priority_ticket(ticket, queue)
    return ticket unless queue.distribution_mode == 'priority_sla'

    backlog = JrcServiceDesk::TicketPolicy::Scope.new(context.to_h, JrcServiceDesk::Ticket).resolve
                                                 .where(unit_id: ticket.unit_id, queue_id: queue.id, assignee_membership_id: nil)
                                                 .joins(:status).where(jrc_service_desk_ticket_statuses: { phase: 'open' })
    selected = JrcServiceDesk::DispatchOrder.apply(backlog).lock('FOR UPDATE OF jrc_service_desk_tickets SKIP LOCKED').first
    authorize!(selected, :assign?) if selected
    selected
  end

  def candidates(ticket, queue)
    memberships = JrcServiceDesk::UnitMembership.where(account_id: context.account.id, unit_id: ticket.unit_id,
                                                       active: true, availability: 'available').where.not(capacity: nil)
    memberships.order(:id).lock.filter_map do |membership|
      next unless eligible?(membership, ticket, queue)

      load = load(membership, ticket)
      next unless load < membership.capacity

      { membership: membership, load: load, last: last_assignment(membership, ticket) || Time.at(0).utc }
    end
  end

  def eligible?(membership, ticket, queue)
    return false unless (queue.required_skills - membership.skills).empty?

    member = membership.account_user
    target = JrcServiceDesk::OperationalContext.new(account: context.account, user: member.user, account_user: member)
    return false unless target.unit_allowed?(ticket.unit) && target.capability?(:tickets_view)

    !ticket.team_id || target.native_team_ids.exists?(id: ticket.team_id)
  end

  def load(membership, ticket)
    JrcServiceDesk::Ticket.where(account_id: context.account.id, unit_id: ticket.unit_id, assignee_membership_id: membership.id)
                          .joins(:status).where(jrc_service_desk_ticket_statuses: { phase: %w[open waiting] }).count
  end

  def last_assignment(membership, ticket)
    JrcServiceDesk::TicketEvent.where(account_id: context.account.id, unit_id: ticket.unit_id, event_type: 'ticket_auto_routed')
                               .where("data ->> 'assignee_membership_id' = ?", membership.id.to_s).maximum(:created_at)
  end

  def choose(candidates, mode)
    if mode == 'round_robin'
      candidates.min_by { |row| [row[:last], row[:membership].id] }
    else
      candidates.min_by { |row| [row[:load], row[:last], row[:membership].id] }
    end
  end
end
