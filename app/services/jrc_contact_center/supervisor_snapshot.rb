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
      JrcContactCenter::AgentStateSnapshot.new(account_user: member).call.merge(name: member.user.available_name)
    end
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
