# frozen_string_literal: true

class JrcServiceDesk::ClaimNextService < JrcServiceDesk::BaseService
  # No browser selection participates in eligibility or concurrency control.
  def call(unit_id:, idempotency_key:)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    with_unit(unit_id) do |unit|
      raise Pundit::NotAuthorizedError unless context.capability?(:tickets_claim)

      membership = actor_membership.reload
      previous = authorized_replay(unit, membership, key)
      next previous if previous

      verify_capacity!(unit, membership)
      candidate = next_candidate(unit, membership)
      next nil unless candidate

      authorize!(candidate, :assign?)
      candidate.update!(assignee_membership: membership)
      JrcServiceDesk::OlaTracker.sync!(candidate)
      record_claim(unit, membership, candidate, key)
      candidate
    end
  end

  private

  def authorized_replay(unit, membership, key)
    previous = JrcServiceDesk::TicketEvent.find_by(account_id: context.account.id, unit_id: unit.id,
                                                   actor_membership_id: membership.id, event_type: 'ticket_claimed', correlation_id: key)
    return unless previous

    authorize!(previous.ticket, :show?)
    previous.ticket
  end

  def verify_capacity!(unit, membership)
    unless membership.availability == 'available' && membership.capacity
      raise JrcServiceDesk::LifecycleDependencyError, 'Explicit availability and capacity required'
    end

    active = JrcServiceDesk::Ticket.where(account_id: context.account.id, unit_id: unit.id, assignee_membership_id: membership.id)
                                   .joins(:status).where(jrc_service_desk_ticket_statuses: { phase: %w[open waiting] }).count
    raise JrcServiceDesk::LifecycleDependencyError, 'Agent capacity reached' if active >= membership.capacity
  end

  def next_candidate(unit, membership)
    scope = JrcServiceDesk::TicketPolicy::Scope.new(context.to_h, JrcServiceDesk::Ticket).resolve
                                               .where(unit_id: unit.id, assignee_membership_id: nil).joins(:status)
                                               .where(jrc_service_desk_ticket_statuses: { phase: 'open' }).includes(:queue)
    # The unit lock serializes capacity changes/claims and the row lock protects ownership.
    JrcServiceDesk::DispatchOrder.apply(scope).lock('FOR UPDATE OF jrc_service_desk_tickets SKIP LOCKED').detect do |ticket|
      eligible?(ticket, membership)
    end
  end

  def record_claim(unit, membership, candidate, key)
    JrcServiceDesk::TicketEvent.create!(
      account: context.account, unit: unit, ticket: candidate, actor_membership: membership,
      event_type: 'ticket_claimed', correlation_id: key, data: { 'assignee_membership_id' => membership.id }
    )
  end

  def eligible?(ticket, membership)
    queue = ticket.queue
    return false if queue && !queue.active?
    return false if ticket.team_id && !context.native_team_ids.exists?(id: ticket.team_id)

    !queue || (queue.required_skills - membership.skills).empty?
  end
end
