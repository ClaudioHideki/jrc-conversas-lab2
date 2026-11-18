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

    member_ids = JrcContactCenter::QueueMembership.where(account: @account, queue_id: @access.queues.select(:id), active: true)
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
    data[:pause_notice] = scoped_pause_notice(snapshot, member, data, permitted)
    data[:pending_qualifications] = data[:pending_qualifications].select do |qualification|
      qualification['call_session_id'] && @access.call_sessions.exists?(id: qualification['call_session_id'])
    end
    data
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
    { elapsed_seconds: elapsed, exceeded: elapsed > maximum * 60 }
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
