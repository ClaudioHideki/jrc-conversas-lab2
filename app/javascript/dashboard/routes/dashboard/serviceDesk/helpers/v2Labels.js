export function v2Labels(t) {
  return {
    visibility: {
      internal: t('JRC_SERVICE_DESK.COCKPIT.visibility.internal'),
      technical_team: t('JRC_SERVICE_DESK.COCKPIT.visibility.technical_team'),
      customer: t('JRC_SERVICE_DESK.COCKPIT.visibility.customer'),
      public_without_notification: t(
        'JRC_SERVICE_DESK.COCKPIT.visibility.public_without_notification'
      ),
    },
    channel: {
      email: t('JRC_SERVICE_DESK.COCKPIT.channels.email'),
      whatsapp: t('JRC_SERVICE_DESK.COCKPIT.channels.whatsapp'),
    },
    delivery: {
      blocked: t('JRC_SERVICE_DESK.COCKPIT.delivery_state.blocked'),
      queued: t('JRC_SERVICE_DESK.COCKPIT.delivery_state.queued'),
      dispatching: t('JRC_SERVICE_DESK.COCKPIT.delivery_state.dispatching'),
      sent: t('JRC_SERVICE_DESK.COCKPIT.delivery_state.sent'),
      delivered: t('JRC_SERVICE_DESK.COCKPIT.delivery_state.delivered'),
      read: t('JRC_SERVICE_DESK.COCKPIT.delivery_state.read'),
      failed: t('JRC_SERVICE_DESK.COCKPIT.delivery_state.failed'),
      unknown: t('JRC_SERVICE_DESK.COCKPIT.delivery_state.unknown'),
    },
    event: {
      first_response_recorded: t(
        'JRC_SERVICE_DESK.OPS.EVENTS.first_response_recorded'
      ),
      ticket_auto_routed: t('JRC_SERVICE_DESK.OPS.EVENTS.ticket_auto_routed'),
      notification_delivery_updated: t(
        'JRC_SERVICE_DESK.OPS.EVENTS.notification_delivery_updated'
      ),
      interaction_republished: t(
        'JRC_SERVICE_DESK.OPS.EVENTS.interaction_republished'
      ),
      task_created: t('JRC_SERVICE_DESK.OPS.EVENTS.task_created'),
      task_updated: t('JRC_SERVICE_DESK.OPS.EVENTS.task_updated'),
      approval_requested: t('JRC_SERVICE_DESK.OPS.EVENTS.approval_requested'),
      approval_decided: t('JRC_SERVICE_DESK.OPS.EVENTS.approval_decided'),
      incident_linked: t('JRC_SERVICE_DESK.OPS.EVENTS.incident_linked'),
      incident_updated: t('JRC_SERVICE_DESK.OPS.EVENTS.incident_updated'),
      clock_threshold_reached: t(
        'JRC_SERVICE_DESK.OPS.EVENTS.clock_threshold_reached'
      ),
      clock_violated: t('JRC_SERVICE_DESK.OPS.EVENTS.clock_violated'),
      approval_escalated: t('JRC_SERVICE_DESK.OPS.EVENTS.approval_escalated'),
      resource_linked: t('JRC_SERVICE_DESK.OPS.EVENTS.resource_linked'),
      resource_updated: t('JRC_SERVICE_DESK.OPS.EVENTS.resource_updated'),
      resource_archived: t('JRC_SERVICE_DESK.OPS.EVENTS.resource_archived'),
      ticket_claimed: t('JRC_SERVICE_DESK.OPS.EVENTS.ticket_claimed'),
      ticket_created: t('JRC_SERVICE_DESK.OPS.EVENTS.ticket_created'),
      ticket_updated: t('JRC_SERVICE_DESK.OPS.EVENTS.ticket_updated'),
      ticket_assigned: t('JRC_SERVICE_DESK.OPS.EVENTS.ticket_assigned'),
      ticket_transferred: t('JRC_SERVICE_DESK.OPS.EVENTS.ticket_transferred'),
      note_added: t('JRC_SERVICE_DESK.OPS.EVENTS.note_added'),
      conversation_linked: t('JRC_SERVICE_DESK.OPS.EVENTS.conversation_linked'),
      sla_snapshot_recorded: t(
        'JRC_SERVICE_DESK.OPS.EVENTS.sla_snapshot_recorded'
      ),
      creation_context_recorded: t(
        'JRC_SERVICE_DESK.OPS.EVENTS.creation_context_recorded'
      ),
      lifecycle_policy_bound: t(
        'JRC_SERVICE_DESK.OPS.EVENTS.lifecycle_policy_bound'
      ),
      lifecycle_transitioned: t(
        'JRC_SERVICE_DESK.OPS.EVENTS.lifecycle_transitioned'
      ),
    },
    approval: {
      pending: t('JRC_SERVICE_DESK.COCKPIT.approval_status.pending'),
      approved: t('JRC_SERVICE_DESK.COCKPIT.approval_status.approved'),
      rejected: t('JRC_SERVICE_DESK.COCKPIT.approval_status.rejected'),
      returned: t('JRC_SERVICE_DESK.COCKPIT.approval_status.returned'),
    },
    feedback: {
      saved: t('JRC_SERVICE_DESK.COCKPIT.saved'),
      conflict: t('JRC_SERVICE_DESK.COCKPIT.conflict'),
      denied: t('JRC_SERVICE_DESK.COCKPIT.denied'),
      error: t('JRC_SERVICE_DESK.COCKPIT.error'),
      scan_unavailable: t('JRC_SERVICE_DESK.COCKPIT.scan_unavailable'),
    },
    task: {
      open: t('JRC_SERVICE_DESK.COCKPIT.task_status.open'),
      in_progress: t('JRC_SERVICE_DESK.COCKPIT.task_status.in_progress'),
      completed: t('JRC_SERVICE_DESK.COCKPIT.task_status.completed'),
      cancelled: t('JRC_SERVICE_DESK.COCKPIT.task_status.cancelled'),
    },
    screen: {
      tasks: t('JRC_SERVICE_DESK.SCREENS.tasks'),
      approvals: t('JRC_SERVICE_DESK.SCREENS.approvals'),
      incidents: t('JRC_SERVICE_DESK.SCREENS.incidents'),
      problems: t('JRC_SERVICE_DESK.SCREENS.problems'),
      reports: t('JRC_SERVICE_DESK.SCREENS.reports'),
      sla: t('JRC_SERVICE_DESK.SCREENS.sla'),
    },
    state: {
      open: t('JRC_SERVICE_DESK.V2.states.open'),
      in_progress: t('JRC_SERVICE_DESK.V2.states.in_progress'),
      completed: t('JRC_SERVICE_DESK.V2.states.completed'),
      cancelled: t('JRC_SERVICE_DESK.V2.states.cancelled'),
      pending: t('JRC_SERVICE_DESK.V2.states.pending'),
      approved: t('JRC_SERVICE_DESK.V2.states.approved'),
      rejected: t('JRC_SERVICE_DESK.V2.states.rejected'),
      returned: t('JRC_SERVICE_DESK.V2.states.returned'),
      investigating: t('JRC_SERVICE_DESK.V2.states.investigating'),
      monitoring: t('JRC_SERVICE_DESK.V2.states.monitoring'),
      resolved: t('JRC_SERVICE_DESK.V2.states.resolved'),
    },
    supervisor: {
      observed_cycles: t('JRC_SERVICE_DESK.V2.observed_cycles'),
      running_breached: t('JRC_SERVICE_DESK.V2.running_breached'),
      completed_met: t('JRC_SERVICE_DESK.V2.completed_met'),
      completed_breached: t('JRC_SERVICE_DESK.V2.completed_breached'),
      first_response_average_seconds: t(
        'JRC_SERVICE_DESK.V2.first_response_average_seconds'
      ),
      resolution_average_seconds: t(
        'JRC_SERVICE_DESK.V2.resolution_average_seconds'
      ),
      attendance_average_seconds: t(
        'JRC_SERVICE_DESK.R3.attendance_average_seconds'
      ),
      evolution: t('JRC_SERVICE_DESK.V2.evolution'),
      top_categories: t('JRC_SERVICE_DESK.V2.top_categories'),
      by_agent: t('JRC_SERVICE_DESK.V2.by_agent'),
    },
    availability: {
      available: t('JRC_SERVICE_DESK.V2.availability.available'),
      unavailable: t('JRC_SERVICE_DESK.V2.availability.unavailable'),
      paused: t('JRC_SERVICE_DESK.V2.availability.paused'),
    },
  };
}
