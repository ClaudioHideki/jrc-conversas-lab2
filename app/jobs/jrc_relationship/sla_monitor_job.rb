class JrcRelationship::SlaMonitorJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(account_id = nil)
    rows = JrcRelationship::Action.where(status: JrcRelationship::Action::ACTIVE_STATUSES).where.not(operations_sla_policy_id: nil).includes(:account)
    rows = rows.where(account_id: account_id) if account_id
    rows.find_each do |action|
      next unless action.account.feature_enabled?('jrc_relationship') && action.account.active?
      Time.use_zone(Time.find_zone(action.account.reporting_timezone) || Time.zone) { evaluate(action) }
    end
  end

  private

  def evaluate(action)
    action.with_lock do
      return if action.sla_paused_at
      snapshot = JrcOperations::SlaClock.new(action).snapshot
      snapshot[:triggered_thresholds].each do |threshold|
        metadata = { threshold: threshold, due_at: snapshot[:total_due_at]&.iso8601 }
        next if JrcCrm::AuditEvent.where(account: action.account, resource_type: action.class.name, resource_id: action.id,
          event_type: 'operations_sla_threshold').where('metadata @> ?', metadata.to_json).exists?
        JrcCrm::AuditEvent.create!(account: action.account, actor_type: 'System', resource_type: action.class.name,
          resource_id: action.id, event_type: 'operations_sla_threshold', metadata: metadata,
          from_value: {}, to_value: { state: snapshot[:state], percent_elapsed: snapshot[:percent_elapsed] })
        JrcRelationship::Notifications.call(action, event: "sla_threshold:#{threshold}:#{metadata[:due_at]}")
      end
      clocks = { first_action: [snapshot[:first_action_overdue], snapshot[:first_action_due_at]],
                 total: [snapshot[:total_overdue], snapshot[:total_due_at]] }
      clocks.each do |kind, (late, due)|
        next unless late
        metadata = { clock_kind: kind.to_s, due_at: due.iso8601 }
        next if JrcCrm::AuditEvent.where(account: action.account, resource_type: action.class.name, resource_id: action.id,
          event_type: 'operations_sla_violated').where('metadata @> ?', metadata.to_json).exists?
        JrcCrm::AuditEvent.create!(account: action.account, actor_type: 'System', resource_type: action.class.name,
          resource_id: action.id, event_type: 'operations_sla_violated', metadata: metadata,
          from_value: {}, to_value: { state: 'overdue' })
        JrcRelationship::Notifications.call(action, event: "sla_#{kind}:#{due.iso8601}")
        escalation_id = action.operations_sla_policy.escalation['user_id']
        next unless escalation_id
        member = action.account.account_users.find_by!(user_id: escalation_id)
        context = JrcRelationship::Context.new(member)
        next unless context.policy.manage? && context.assignments.exists?(id: action.assignment_id)
        old_owner = action.owner_id
        action.update!(owner_id: member.user_id, priority: 100)
        action.activity.update!(user_id: member.user_id) if action.activity
        context.audit!(action, before: { owner_id: old_owner }, after: { owner_id: member.user_id }, action: 'sla_escalated')
      end
    end
  end
end
