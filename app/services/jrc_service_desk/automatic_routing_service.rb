# frozen_string_literal: true

class JrcServiceDesk::AutomaticRoutingService < JrcServiceDesk::BaseService
  def preview(unit_id:, queue_id:, options: {}, queue_attributes: {})
    @context = fresh_context!
    unit = context.unit_scope.find(JrcServiceDesk::Input.id(unit_id))
    raise Pundit::NotAuthorizedError unless context.capability?(:tickets_assign)

    queue = JrcServiceDesk::Queue.where(account: context.account, unit: unit, active: true).find(JrcServiceDesk::Input.id(queue_id))
    authorize!(queue, :show?)
    queue.assign_attributes(JrcServiceDesk::ConfigurationContract.attributes('queues', queue_attributes, create: false)) if queue_attributes.any?
    authorize!(queue.team, :show?) if queue.team
    raise ActiveRecord::RecordInvalid, queue unless queue.valid?

    ticket = JrcServiceDesk::Ticket.new(account: context.account, unit: unit, queue: queue, team_id: queue.team_id)
    rows = candidates(ticket, queue, lock: false)
    chosen = select_candidate(ticket, queue, options, rows: rows)
    { queue_id: queue.id, mode: options.fetch('mode', 'queue'), queue_distribution: queue.distribution_mode,
      eligible_members: rows.size, proposed_account_user_id: chosen&.dig(:membership)&.account_user_id, creates_assignment: false }
  end

  def call(ticket_id:)
    with_ticket(ticket_id, :assign?) do |ticket|
      queue = ticket.queue
      options = assignment_options(ticket)
      next ticket unless routable?(ticket, queue)

      # A new routing event can only assign its own ticket. Administrative backlog
      # recovery is a separate explicit operation and never runs on deploy/restart.

      chosen = select_candidate(ticket, queue, options)
      if !chosen && options['fallback_queue_id'] && options['fallback_queue_id'] != queue.id
        target = JrcServiceDesk::Queue.where(account: context.account, unit: ticket.unit, active: true).find(options['fallback_queue_id'])
        JrcServiceDesk::TransferTicketService.new(user_context: context.to_h).call(ticket_id: ticket.id,
          attributes: { 'queue_id' => target.id }, expected_lock_version: ticket.lock_version)
        ticket.reload
        append_event!(ticket, 'resource_updated', 'routing_fallback' => true, 'from_queue_id' => queue.id, 'to_queue_id' => target.id)
        queue = target
        chosen = select_candidate(ticket, queue, options.except('account_user_id').merge('mode' => 'queue'))
      end
      unless chosen
        proof = { 'routing_no_candidate' => true, 'queue_id' => queue.id, 'mode' => queue.distribution_mode,
                  'queue_policy_revision' => queue.current_policy_version&.digest }
        unless ticket.ticket_events.where(event_type: 'resource_updated').exists?(['data @> ?::jsonb', proof.to_json])
          append_event!(ticket, 'resource_updated', proof.merge('reason' => (@candidate_reasons || {}).keys.sort.join(',').presence || 'no_eligible_agents'))
        end
        next ticket
      end

      member = chosen[:membership]
      member.account_user.with_lock do
        member.reload
        # Refresh presence, account flag, capabilities, skills and capacity immediately
        # before persistence while membership and AccountUser revocations are locked out.
        reason = JrcServiceDesk::AssignmentEligibility.new(membership: member, ticket: ticket).reason
        if reason
          append_event!(ticket, 'resource_updated', 'routing_no_candidate' => true, 'queue_id' => queue.id,
            'mode' => queue.distribution_mode, 'reason' => reason)
          next
        end

        ticket.assignee_membership = member
        ticket.save!
        append_event!(ticket, 'ticket_auto_routed', 'assignee_membership_id' => ticket.assignee_membership_id,
                                                    'queue_id' => queue.id, 'mode' => queue.distribution_mode)
      end
      ticket
    end
  end

  private

  def routable?(ticket, queue)
    queue&.active? && queue.distribution_mode != 'manual' &&
      !ticket.assignee_membership_id && ticket.status.phase == 'open'
  end

  def assignment_options(ticket)
    binding = ticket.catalogue_snapshot.dig('operational_rules', 'routing')
    return {} unless binding

    version = JrcServiceDesk::OperationalRuleVersion.where(account: context.account, unit: ticket.unit).find(binding.fetch('version_id'))
    raise JrcServiceDesk::IdempotencyConflict unless version.digest == binding['digest'] && version.digest == version.expected_digest

    rule = version.definition.fetch('rules').find { |row| row['key'] == binding['key'] } || raise(JrcServiceDesk::IdempotencyConflict)
    return {} unless ticket.queue_id == rule['output']['queue_id']

    JrcServiceDesk::OperationalRuleReferences.new(context: context, unit: ticket.unit).validate_rule!(rule)
    rule['output'].fetch('assignment', {})
  end

  def select_candidate(ticket, queue, options, rows: nil)
    return nil if queue.distribution_mode == 'manual'

    rows ||= candidates(ticket, queue)
    if %w[fixed hybrid].include?(options['mode'])
      fixed = rows.find { |row| row[:membership].account_user_id == options['account_user_id'] }
      return fixed if fixed || options['mode'] == 'fixed'
    end
    choose(rows, queue.distribution_mode)
  end

  def candidates(ticket, _queue, lock: true)
    memberships = JrcServiceDesk::UnitMembership.operational.where(account_id: context.account.id, unit_id: ticket.unit_id,
                                                                   active: true, availability: 'available').where.not(capacity: nil)
    memberships = memberships.order(:id)
    memberships = memberships.lock if lock
    presence = OnlineStatusTracker.effective_presence(context.account.id)
    @candidate_reasons = Hash.new(0)
    memberships.filter_map do |membership|
      reason = JrcServiceDesk::AssignmentEligibility.new(membership: membership, ticket: ticket, presence: presence).reason
      if reason
        @candidate_reasons[reason] += 1
        next
      end

      load = load(membership, ticket)
      next unless load < membership.capacity

      { membership: membership, load: load, last: last_assignment(membership, ticket) || Time.at(0).utc }
    end
  end

  def load(membership, ticket)
    JrcServiceDesk::RecordWithdrawal.excluding(JrcServiceDesk::Ticket.all, :ticket).where(account_id: context.account.id, unit_id: ticket.unit_id,
                                                                                          assignee_membership_id: membership.id)
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
