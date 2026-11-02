# frozen_string_literal: true

# Shared by previews, new-event routing, catalogue defaults and operational diagnostics.
class JrcServiceDesk::AssignmentEligibility
  def initialize(membership:, ticket: nil, presence: nil)
    @membership = membership
    @ticket = ticket
    @presence = presence
  end

  def reason
    return 'membership_inactive' unless @membership.active? && !@membership.administrative_actor?

    member = @membership.account_user.reload
    return 'agent_auto_assignment_disabled' unless member.auto_assignment_enabled?

    context = JrcServiceDesk::OperationalContext.new(account: @membership.account, user: member.user, account_user: member)
    return 'permission_denied' unless context.operational_unit_allowed?(@membership.unit) && context.capability?(:tickets_view)
    return 'operational_unavailable' unless @membership.availability == 'available'
    return 'capacity_missing' unless @membership.capacity
    return 'configured_offline' unless member.availability == 'online'

    presence = @presence || OnlineStatusTracker.effective_presence(@membership.account_id)
    return presence[:reason] if presence[:reason]
    return 'no_effective_presence' unless presence[:user_ids].include?(member.user_id)
    domain = domain_reason(context) if @ticket
    return domain if domain
    return 'capacity_reached' if load >= @membership.capacity

    nil
  end

  def load
    JrcServiceDesk::RecordWithdrawal.excluding(JrcServiceDesk::Ticket.all, :ticket)
      .where(account_id: @membership.account_id, unit_id: @membership.unit_id, assignee_membership_id: @membership.id)
      .joins(:status).where(jrc_service_desk_ticket_statuses: { phase: %w[open waiting] }).count
  end

  def self.manual_domain?(membership, ticket, manual: true)
    return false unless (!manual || membership.manual_assignment_enabled?) && membership.active? && !membership.administrative_actor?
    return false if membership.team_id && membership.team_id != ticket.team_id
    return false if membership.queue_id && membership.queue_id != ticket.queue_id

    member = membership.account_user
    context = JrcServiceDesk::OperationalContext.new(account: membership.account, user: member.user, account_user: member)
    context.capability?(:tickets_view) && context.operational_unit_allowed?(ticket.unit) &&
      context.supervision_access.allowed?(ticket, 'tickets_view') &&
      (!ticket.team_id || context.native_team_ids.exists?(id: ticket.team_id))
  end

  private

  def domain_reason(context)
    return 'unit_restriction' unless @ticket.account_id == @membership.account_id && @ticket.unit_id == @membership.unit_id
    return 'team_restriction' if @membership.team_id && @membership.team_id != @ticket.team_id
    return 'queue_restriction' if @membership.queue_id && @membership.queue_id != @ticket.queue_id
    return 'team_restriction' if @ticket.team_id && !context.native_team_ids.exists?(id: @ticket.team_id)
    return 'supervision_restriction' unless context.supervision_access.allowed?(@ticket, 'tickets_view')
    return 'queue_distribution_manual' if @ticket.queue&.distribution_mode == 'manual'
    return 'skills_missing' if @ticket.queue && (@ticket.queue.required_skills - @membership.skills).any?

    nil
  end
end
