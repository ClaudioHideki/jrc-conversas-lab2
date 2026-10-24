# frozen_string_literal: true

# Read-only plans: every step is still executed by LifecycleTransitionService.
# An offered resolve action alone is never presented as a complete closure.
class JrcServiceDesk::ClosureOptions
  def initialize(ticket:, context:, version:, options:, revision: nil)
    @ticket, @context, @version, @options = ticket, context, version, options
    @revision = revision || JrcServiceDesk::ClosureRevisionBinding.new(ticket, version)
  end

  def call
    return [] unless @version
    return [] if unavailable_reason
    policy = JrcServiceDesk::LifecycleActionPolicy.new(@context, @ticket)
    return [] unless policy.action?('close') && policy.view_notes?

    direct = @options.select { |rule| rule[:action] == 'close' }.map { |rule| plan([rule]) }
    return direct if direct.any?

    @options.select { |rule| rule[:action] == 'resolve' }.flat_map do |resolve|
      @version.definition.fetch('transitions').map { |rule| @revision.rule(rule) }.filter_map do |close|
        next unless close['action'] == 'close' && close['from_status_ids'].include?(resolve[:to_status_id].to_i)
        next unless policy.requirements_allowed?(close.fetch('requirements'))
        target = JrcServiceDesk::TicketStatus.find_by(account_id: @ticket.account_id, unit_id: @ticket.unit_id, id: close['to_status_id'], active: true)
        next unless target && target.phase == 'closed' && @version.status_phases[target.id.to_s] == target.phase

        plan([resolve, { key: close['key'], action: 'close', to_status_id: target.id.to_s,
                         to_status_name: target.name, requirements: close['requirements'], reasons: [] }])
      end
    end
  end

  def unavailable_reason
    return unless @ticket.service&.approval_required?
    policy = JrcServiceDesk::LifecycleActionPolicy.new(@context, @ticket)
    return unless policy.action?('close') && policy.view_notes?

    cycle_start = @ticket.lifecycle_transitions.where(action: 'reopen').maximum(:occurred_at) || @ticket.opened_at
    approvals = @ticket.ticket_approvals.where('created_at >= ?', cycle_start)
    approved = approvals.exists?(status: 'approved') && !approvals.exists?(status: %w[pending rejected returned])
    'service_approval_required' unless approved
  end

  private

  def plan(steps)
    { key: steps.map { |row| row[:key] }.join(':'), steps: steps }
  end
end
