# frozen_string_literal: true

# Read-only: inspecting a ticket never pins a policy, creates clocks or pauses time.
class JrcServiceDesk::LifecycleReadService
  def initialize(user_context:, ticket:)
    @context, @ticket = user_context, ticket
  end

  def call(page: 1)
    Pundit.authorize(@context, @ticket, :inspect?, policy_class: JrcServiceDesk::LifecycleActionPolicy)
    version = JrcServiceDesk::LifecycleSelector.new(@ticket).applicable
    dependency = nil
    if version && version.definition['sla']['mode'] == 'calendar_snapshot'
      cycle = @ticket.sla_cycles.order(number: :desc).first
      begin
        JrcServiceDesk::LifecycleClocks.verify_snapshot!(cycle&.sla_snapshot || @ticket.latest_sla_snapshot)
      rescue JrcServiceDesk::LifecycleDependencyError, TZInfo::InvalidTimezoneIdentifier
        dependency = 'calendar_snapshot_required'
      end
    end
    pause = @ticket.lifecycle_pauses.find_by(ended_at: nil)
    options = if version && !dependency
                version.definition['transitions'].select do |rule|
                  next false unless JrcServiceDesk::LifecycleActionPolicy.new(@context, @ticket).action?(rule['action'])
                  next false unless JrcServiceDesk::LifecycleActionPolicy.new(@context, @ticket).requirements_allowed?(rule['requirements'])
                  next false unless rule['from_status_ids'].include?(@ticket.status_id)
                  target = JrcServiceDesk::TicketStatus.find_by(account_id: @ticket.account_id, unit_id: @ticket.unit_id, id: rule['to_status_id'], active: true)
                  next false unless target && version.status_phases[target.id.to_s] == target.phase && version.status_phases[@ticket.status_id.to_s] == @ticket.status.phase
                  next false if (rule['action'] == 'pause' && pause) || (rule['action'] == 'resume' && !pause)
                  next false if pause && !%w[resume pause].include?(rule['action']) && !rule['end_pause']
                  if rule['action'] == 'reopen'
                    config = version.definition['reopen']
                    anchor = @ticket.lifecycle_transitions.where(action: config['anchor_action']).order(occurred_at: :desc, id: :desc).first
                    begin
                      version.rules.reopen_check!(now: Time.current, anchor: anchor&.occurred_at)
                    rescue ArgumentError
                      next false
                    end
                  end
                  true
                end.map do |rule|
                  { key: rule['key'], action: rule['action'], to_status_id: rule['to_status_id'].to_s,
                    to_status_name: JrcServiceDesk::TicketStatus.find(rule['to_status_id']).name,
                    requirements: rule['requirements'], reasons: rule['action'] == 'pause' ? version.definition['pause_reasons'].select { |r| r['status_ids'].include?(rule['to_status_id']) }.map { |r| r.slice('code', 'name', 'clocks') } : [] }
                end
              else
                []
              end
    history = @ticket.lifecycle_transitions.order(occurred_at: :desc, id: :desc)
    page = JrcServiceDesk::Input.id(page)
    cycle = @ticket.sla_cycles.order(number: :desc).first
    { contract_version: 1, account_id: @ticket.account_id.to_s, unit_id: @ticket.unit_id.to_s, ticket_id: @ticket.id.to_s,
      lock_version: @ticket.lock_version, service_id: @ticket.service_id&.to_s,
      policy: version && { id: version.id.to_s, version: version.version, digest: version.digest, pinned: @ticket.lifecycle_policy_version_id == version.id },
      reopening: reopening_summary(version),
      unavailable_reason: version ? dependency : 'no_applicable_policy', options: options,
      pause: pause && { id: pause.id.to_s, reason_code: pause.reason_code, clocks: pause.clocks, started_at: pause.started_at.iso8601(6) },
      cycle: cycle && { id: cycle.id.to_s, number: cycle.number, snapshot_version: cycle.sla_snapshot.version,
        timezone: cycle.sla_snapshot.timezone, clocks: cycle.sla_clocks.order(:kind).map { |c| clock(c) } },
      history: history.offset((page - 1) * 20).limit(20).map { |r| transition(r) },
      meta: { page: page, per_page: 20, total: history.count } }
  end

  def transition(record)
    Pundit.authorize(@context, @ticket, :view_history?)
    raise Pundit::NotAuthorizedError unless record.ticket_id == @ticket.id && record.account_id == @ticket.account_id && record.unit_id == @ticket.unit_id
    { id: record.id.to_s, ticket_id: record.ticket_id.to_s, account_id: record.account_id.to_s, unit_id: record.unit_id.to_s,
      policy_version_id: record.lifecycle_policy_version_id.to_s, policy_version: record.lifecycle_policy_version.version,
      action: record.action, rule_key: record.rule_key, request_key: record.request_key,
      from_status_id: record.from_status_id.to_s, to_status_id: record.to_status_id.to_s,
      author: { account_user_id: record.actor_membership.account_user_id.to_s, name: record.actor_membership.account_user.user.name },
      occurred_at: record.occurred_at.iso8601(6), payload: JrcServiceDesk::HistoryProjection.lifecycle(record.payload,
        notes: JrcServiceDesk::TicketPolicy.new(@context, @ticket).view_notes?,
        sla: JrcServiceDesk::TicketPolicy.new(@context, @ticket).view_sla?) }
  end

  private

  def reopening_summary(version)
    return nil unless version && version.definition['reopen']['allowed']
    config = version.definition['reopen']
    anchor = @ticket.lifecycle_transitions.where(action: config['anchor_action']).order(occurred_at: :desc, id: :desc).first
    { window_seconds: config['window_seconds'], expired_behavior: config['expired'], sla_cycle: config['sla_cycle'],
      expires_at: anchor && (anchor.occurred_at + config['window_seconds']).iso8601(6) }
  end

  def clock(c)
    { id: c.id.to_s, kind: c.kind, state: c.state, budget_seconds: c.budget_seconds, elapsed_seconds: c.elapsed_seconds.to_f,
      due_at: c.due_at.iso8601(6), achieved_at: c.achieved_at&.iso8601(6), anchor_at: c.anchor_at.iso8601(6), met: c.met? }
  end
end
