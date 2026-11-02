# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::AutomationInsightsController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def ola
    ctx, unit, values, tickets = scoped_input(%i[queues_manage sla_view])
    queues = policy_scope(::JrcServiceDesk::Queue).where(account_id: ctx.account.id, unit_id: unit.id)
    queue = values['queue_id'].present? ? queues.find(::JrcServiceDesk::Input.id(values['queue_id'])) : nil
    authorize queue, :show? if queue
    page = ::JrcServiceDesk::Input.id(values.fetch('page', 1))
    days = days_for(values)
    observed = Time.current
    clocks = ::JrcServiceDesk::OlaClock.where(account_id: ctx.account.id, unit_id: unit.id, queue_id: queue ? queue.id : queues.select(:id),
                                              ticket_id: tickets.select(:id)).where('started_at >= ?', observed - days.days)
    counts = Hash.new(0)
    measurements = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    daily = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    clocks.includes(:sla_snapshot).find_each do |clock|
      projection = ::JrcServiceDesk::ClockProjection.new(clock, now: observed).call
      counts[projection[:state]] += 1
      measurements[clock.kind][projection[:deadline_state]] += 1
      daily[clock.started_at.utc.to_date.iso8601][projection[:deadline_state]] += 1
      counts[projection[:deadline_state]] += 1 unless projection[:deadline_state] == projection[:state]
      if projection[:state] == 'completed'
        counts[projection[:breached] ? 'completed_breached' : 'completed_met'] += 1
      end
    end
    total = clocks.count
    exporting = values['export'] == 'true'
    raise ArgumentError, 'Narrow the period before exporting more than 10000 measurements' if exporting && total > 10_000

    selected = clocks.includes(:ticket, :sla_snapshot).order(id: :desc)
    selected = selected.offset((page - 1) * 25).limit(25) unless exporting
    rows = selected.map do |clock|
      ::JrcServiceDesk::ClockProjection.new(clock, now: observed).call.merge(ticket_id: clock.ticket_id.to_s,
                                                                             title: clock.ticket.title, queue_id: clock.queue_id.to_s, policy_revision: clock.policy_revision)
    end
    render json: base_payload.merge(unit_id: unit.id.to_s, queue_id: queue&.id&.to_s, queues_total: queues.count, active_queues: queues.where(active: true).count, observed_at: observed.iso8601(6),
                                    days: days, timezone: 'UTC', total: total, page: page, per_page: exporting ? total : 25, counts: counts, measurements: measurements, daily: daily.sort.to_h, items: rows)
  end

  def clock_alerts
    ctx, unit, values, tickets = scoped_input(%i[queues_manage sla_view])
    relation = ::JrcServiceDesk::ClockAlertDelivery.where(account_id: ctx.account.id, unit_id: unit.id, ticket_id: tickets.select(:id))
    relation = relation.where('jrc_service_desk_clock_alert_deliveries.created_at >= ?', days_for(values).days.ago)
    if values['queue_id']
      queue = Pundit.policy_scope!(ctx.to_h, ::JrcServiceDesk::Queue).where(unit_id: unit.id).find(::JrcServiceDesk::Input.id(values['queue_id']))
      relation = relation.joins(:ticket_event).where(
        "jrc_service_desk_ticket_events.data->>'clock_id' IN (SELECT id::text FROM jrc_service_desk_ola_clocks WHERE account_id=? AND unit_id=? AND queue_id=?)", ctx.account.id, unit.id, queue.id
      )
    end
    page = ::JrcServiceDesk::Input.id(values.fetch('page', 1))
    render json: base_payload.merge(unit_id: unit.id.to_s, total: relation.count, counts: relation.group(:state).count,
                                    items: relation.order(id: :desc).offset((page-1)*25).limit(25).includes(recipient_account_user: :user).map do |row|
                                      { id: row.id.to_s, ticket_id: row.ticket_id.to_s, channel: row.channel, state: row.state, reason: row.reason,
                                        recipient_name: row.recipient_account_user.user.name, attempts: row.attempts,
                                        retryable: %w[blocked failed].include?(row.state) && row.attempts < 3, accepted_at: row.accepted_at&.iso8601(6) }
                                    end)
  end

  def retry_clock_alert
    values = body_values(%w[unit_id alert_id expected_attempts reason])
    unit = policy_scope(::JrcServiceDesk::Unit).find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize unit, :show?
    ::JrcServiceDesk::RetryClockAlertService.new(user_context: pundit_user).call(**values.symbolize_keys)
    render json: base_payload.merge(unit_id: values['unit_id'].to_s, applied: true, queued: true)
  end

  def notifications
    ctx, unit, values, tickets = scoped_input(%i[notifications_manage history_view])
    days = days_for(values)
    deliveries = ::JrcServiceDesk::NotificationDelivery.where(account_id: ctx.account.id, unit_id: unit.id,
                                                              ticket_id: tickets.select(:id)).where('created_at >= ?', days.days.ago)
    counts = deliveries.group(:state).count
    sent = %w[sent delivered read].sum { |key| counts.fetch(key, 0) }
    delivered = %w[delivered read].sum { |key| counts.fetch(key, 0) }
    # No assertion of delivery for queued, unknown or failed operations.
    customers = tickets.where(id: deliveries.where(state: %w[sent delivered read]).select(:ticket_id)).distinct.count(:requester_id)
    versions = ::JrcServiceDesk::NotificationPolicyVersion.where(account_id: ctx.account.id, unit_id: unit.id)
    current = versions.group(:event_type, :channel, :ticket_type_id, :service_id).maximum(:id).values
    render json: base_payload.merge(unit_id: unit.id.to_s, days: days, timezone: 'UTC', states: counts,
                                    active_policies: versions.where(id: current, enabled: true).count, confirmed_sent: sent, confirmed_delivered: delivered,
                                    delivery_rate: sent.positive? ? (delivered * 100.0 / sent).round(1) : nil, notified_requesters: customers)
  end

  private

  def scoped_input(required)
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id queue_id days page assignee_account_user_id team_id export])
    ctx = ::JrcServiceDesk::OperationalContext.new(pundit_user)
    raise Pundit::NotAuthorizedError unless (required + %i[dashboard_view tickets_view_all]).all? { |cap| ctx.capability?(cap) }

    unit = ctx.unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize unit, :show?
    tickets = ::JrcServiceDesk::TicketPolicy::Scope.new(ctx.to_h, ::JrcServiceDesk::Ticket)
      .resolve_for(required.include?(:sla_view) ? 'sla_view' : 'history_view').where(account_id: ctx.account.id, unit_id: unit.id)
    if values['assignee_account_user_id'].present?
      membership = ::JrcServiceDesk::UnitMembership.operational.where(account_id: ctx.account.id, unit_id: unit.id, active: true,
                                                                      account_user_id: ::JrcServiceDesk::Input.id(values['assignee_account_user_id'])).take!
      tickets = tickets.where(assignee_membership_id: membership.id)
    end
    if values['team_id'].present?
      team = ctx.account.teams.find(::JrcServiceDesk::Input.id(values['team_id']))
      authorize team, :show?
      tickets = tickets.where(team_id: team.id)
    end
    raise ArgumentError if values['export'] && values['export'] != 'true'

    [ctx, unit, values, tickets]
  end

  def days_for(values)
    days = ::JrcServiceDesk::Input.id(values.fetch('days', 30))
    raise ArgumentError, 'Period must be between 1 and 90 days' unless days.between?(1, 90)

    days
  end
end
