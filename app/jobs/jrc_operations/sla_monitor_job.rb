module JrcOperations
  class SlaMonitorJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform(account_id = nil)
      scope = JrcCrm::BackofficeRequest.where(status: JrcCrm::BackofficeRequest::ACTIVE_STATUSES)
                                          .where.not(operations_sla_policy_id: nil)
                                          .includes(:account, :operations_sla_policy, sales_order: [:deal, :contact])
      scope = scope.where(account_id: account_id) if account_id.present?
      scope.find_each do |request|
        Time.use_zone(Time.find_zone(request.account.reporting_timezone) || Time.zone) { evaluate(request) }
      end
    end

    private

    def evaluate(request)
      request.with_lock do
        return if request.sla_paused_at.present?
        snapshot = JrcOperations::SlaClock.new(request).snapshot
        audit_violations!(request, snapshot)
        Array(snapshot[:triggered_thresholds]).each do |threshold|
          next if threshold_event_exists?(request, threshold)

          audit_threshold!(request, threshold, snapshot)
          create_operational_alert!(request, threshold, snapshot) if threshold.to_f >= 75
          escalate!(request, threshold, snapshot) if threshold.to_f >= 100
        end
      end
    rescue StandardError => e
      Rails.logger.warn("JRC Operations SLA monitor failed for BackofficeRequest##{request.id}: #{e.class}: #{e.message}")
    end

    def threshold_event_exists?(request, threshold)
      JrcCrm::AuditEvent.for_resource('JrcCrm::BackofficeRequest', request.id)
                        .where(event_type: 'operations_sla_threshold')
                        .where('metadata @> ?', { threshold: threshold }.to_json).exists?
    end

    def audit_violations!(request, snapshot)
      clocks = {
        first_action: [snapshot[:first_action_overdue], snapshot[:first_action_due_at]],
        stage: [snapshot[:stage_overdue], snapshot[:stage_due_at]],
        total: [snapshot[:total_overdue], snapshot[:total_due_at]]
      }
      clocks.each do |kind, (overdue, due)|
        next unless overdue

        metadata = { clock_kind: kind.to_s, due_at: due.iso8601 }
        events = JrcCrm::AuditEvent.for_resource('JrcCrm::BackofficeRequest', request.id)
        next if events.where(event_type: 'operations_sla_violated').where('metadata @> ?', metadata.to_json).exists?

        JrcCrm::AuditEvent.create!(account_id: request.account_id, actor_type: 'System',
          event_type: 'operations_sla_violated', resource_type: 'JrcCrm::BackofficeRequest', resource_id: request.id,
          from_value: {}, to_value: { state: 'overdue' }, metadata: metadata.merge(source: 'jrc_operations_sla'))
        escalate!(request, 100, snapshot)
      end
    end

    def audit_threshold!(request, threshold, snapshot)
      JrcCrm::AuditEvent.create!(
        account_id: request.account_id, actor_type: 'System', actor_id: nil,
        event_type: 'operations_sla_threshold', resource_type: 'JrcCrm::BackofficeRequest', resource_id: request.id,
        from_value: {}, to_value: { threshold: threshold, state: snapshot[:state] },
        metadata: { source: 'jrc_operations_sla', threshold: threshold, percent_elapsed: snapshot[:percent_elapsed],
                    sla_due_at: snapshot[:total_due_at] }
      )
    end

    def create_operational_alert!(request, threshold, snapshot)
      order = request.sales_order
      return unless order.deal && request.owner

      marker = { backoffice_request_id: request.id, sla_threshold: threshold }
      return if order.account.jrc_crm_activities.where("metadata @> ?", marker.to_json).exists?

      activity = order.account.jrc_crm_activities.new(
        activity_type: 'task', title: "SLA #{threshold.to_i}% — #{request.request_number}",
        description: "Solicitação #{request.request_number} atingiu #{threshold.to_i}% do SLA total (#{snapshot[:state]}).",
        due_at: snapshot[:total_due_at] || snapshot[:stage_due_at] || snapshot[:first_action_due_at], user: request.owner, deal: order.deal, contact: order.contact,
        metadata: marker.merge(source: 'jrc_operations_sla')
      )
      JrcCrm::ActivityDispatchService.new(activity: activity, actor: request.owner).call
    end

    def escalate!(request, threshold, snapshot)
      escalation = (request.operations_sla_policy.escalation || {}).with_indifferent_access
      user_id = escalation[:user_id].to_i
      return if user_id.zero? || request.owner_id == user_id

      user = request.account.users.find_by(id: user_id)
      return unless user

      previous_owner = request.owner_id
      request.update!(owner: user)
      JrcCrm::AuditEvent.create!(
        account_id: request.account_id, actor_type: 'System', actor_id: nil,
        event_type: 'operations_sla_escalated', resource_type: 'JrcCrm::BackofficeRequest', resource_id: request.id,
        from_value: { owner_id: previous_owner }, to_value: { owner_id: user.id },
        metadata: { source: 'jrc_operations_sla', threshold: threshold, state: snapshot[:state] }
      )
    end
  end
end
