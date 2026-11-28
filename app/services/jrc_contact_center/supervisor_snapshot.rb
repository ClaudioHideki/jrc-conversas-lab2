# frozen_string_literal: true

class JrcContactCenter::SupervisorSnapshot
  def initialize(access:)
    @access = access
    @account = access.account
  end

  def call
    {
      observed_at: Time.current, agents: agents, queues: queues,
      calls: @access.call_sessions.group(:status).count,
      sla: { value: nil, status: 'pending_operational_rules' },
      metrics: JrcContactCenter::MetricsSummary.new(scope: @access.daily_facts, from: Time.zone.today, to: Time.zone.today).call
    }
  end

  private

  def agents
    return @agents if @agents

    member_ids = JrcContactCenter::QueueMembership.where(account: @account, queue_id: @access.queues.select(:id), active: true, role: 'agent')
                                                  .select(:account_user_id)
    @agents = @account.account_users.where(id: member_ids).includes(:user).order(:id).map do |member|
      scoped_agent_data(member).merge(name: member.user.available_name)
    end
  end

  def scoped_agent_data(member)
    snapshot = JrcContactCenter::AgentStateSnapshot.new(account_user: member)
    data = snapshot.call
    permitted = @access.queues.pluck(:id).map(&:to_s)
    data[:queues] = data[:queues].select { |queue| permitted.include?(queue[:id]) }
    data[:eligible_queue_ids] &= permitted
    data[:reason_code] = nil if hidden_pause_reason?(snapshot, permitted)
    data[:state_notice] = scoped_state_notice(snapshot, data)
    data[:pause_notice] = scoped_pause_notice(snapshot, member, data, permitted)
    data[:deferred_pause_notice] = scoped_deferred_pause_notice(member, permitted)
    data[:pending_qualifications] = scoped_pending_qualifications(data[:pending_qualifications])
    data
  end

  # Reuse the already filtered current memberships. Never derive the time of
  # a hidden queue or reuse an old state timestamp for projected pending ACW.
  def scoped_state_notice(snapshot, data)
    event = snapshot.current
    return unless event && event.state == data[:state] && data[:queues].any? { |queue| queue[:id] == event.queue_id.to_s }
    return if data[:eligibility_reason] == 'access_revoked'

    { state: event.state, state_version: event.id.to_s, elapsed_seconds: [Time.current - event.started_at, 0].max.floor }
  end

  def scoped_pending_qualifications(records)
    records.select do |qualification|
      qualification['call_session_id'] && @access.call_sessions.exists?(id: qualification['call_session_id'])
    end
  end

  # Only an operational state for a currently supervised queue; never the private request body or UUID.
  def scoped_deferred_pause_notice(member, permitted)
    queues = JrcContactCenter::QueueMembership.where(
      account: @account, account_user: member, active: true, queue_id: permitted
    ).select(:queue_id)
    record = JrcContactCenter::DeferredPauseRequest.active.find_by(account: @account, account_user: member, queue_id: queues)
    { state: record.state } if record
  end

  # Derive a bounded operational signal; never copy private operator metadata into this response.
  def scoped_pause_notice(snapshot, member, data, permitted)
    event = snapshot.current
    return unless visible_current_pause?(data, event, permitted)
    return unless snapshot.memberships.exists?(queue_id: event.queue_id)

    definition = JrcContactCenter::PauseDefinitionSnapshot.call(event: event, member: member, memberships: snapshot.memberships)
    maximum = definition&.fetch('maximum_minutes', nil)
    return unless maximum.is_a?(Integer)

    elapsed = [Time.current - event.started_at, 0].max.floor
    notice = { elapsed_seconds: elapsed, exceeded: elapsed > maximum * 60 }
    notice[:time_alert_enabled] = definition['time_alert_enabled'] if definition.key?('time_alert_enabled')
    notice
  end

  def visible_current_pause?(data, event, permitted)
    data[:state] == 'paused' && event&.queue_id && permitted.include?(event.queue_id.to_s)
  end

  def hidden_pause_reason?(snapshot, permitted)
    queue_id = snapshot.current&.queue_id
    queue_id && permitted.exclude?(queue_id.to_s)
  end

  def queues
    @access.queues.order(:id).map do |queue|
      calls = @access.call_sessions.where(current_queue_id: queue.id)
      {
        id: queue.id.to_s, name: queue.name, unit_id: queue.unit_id.to_s, status: queue.status,
        waiting: calls.where(status: 'queued').count, offered: calls.where(status: 'ringing').count,
        in_service: calls.where(status: %w[connected held transferring]).count,
        eligible_agents: eligible_agents(queue.id)
      }
    end
  end

  def eligible_agents(queue_id)
    agents.count { |agent| agent[:eligible_queue_ids].include?(queue_id.to_s) }
  end
end
