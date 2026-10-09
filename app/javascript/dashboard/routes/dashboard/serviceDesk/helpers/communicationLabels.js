export function communicationLabels(t) {
  return {
    unavailable: t('JRC_SERVICE_DESK.R2.unavailable'),
    recipient: t('JRC_SERVICE_DESK.R2.recipient'),
    choose_recipient: t('JRC_SERVICE_DESK.R2.choose_recipient'),
    portal_only: t('JRC_SERVICE_DESK.R2.portal_only'),
    review: t('JRC_SERVICE_DESK.R2.review'),
    literal_preview: t('JRC_SERVICE_DESK.R2.literal_preview'),
    preview_invalid: t('JRC_SERVICE_DESK.R2.preview_invalid'),
    published_blocked: t('JRC_SERVICE_DESK.R2.published_blocked'),
    saved: t('JRC_SERVICE_DESK.R2.saved'),
    uncertain: t('JRC_SERVICE_DESK.R2.uncertain'),
    denied: t('JRC_SERVICE_DESK.R2.denied'),
    timeline: t('JRC_SERVICE_DESK.R2.timeline'),
    more: t('JRC_SERVICE_DESK.R2.more'),
    empty: t('JRC_SERVICE_DESK.R2.empty'),
    resend: t('JRC_SERVICE_DESK.R2.resend'),
    reconcile: t('JRC_SERVICE_DESK.R2.reconcile'),
    resend_reason: t('JRC_SERVICE_DESK.R2.resend_reason'),
    confirm_resend: t('JRC_SERVICE_DESK.R2.confirm_resend'),
    attempt: t('JRC_SERVICE_DESK.R2.attempt'),
    policy_version: t('JRC_SERVICE_DESK.R2.policy_version'),
    provider: t('JRC_SERVICE_DESK.R2.provider'),
    executor: t('JRC_SERVICE_DESK.R2.executor'),
    receipt: t('JRC_SERVICE_DESK.R2.receipt'),
    notification_policies: t('JRC_SERVICE_DESK.R2.notification_policies'),
    event_type: t('JRC_SERVICE_DESK.R2.event_type'),
    channel: t('JRC_SERVICE_DESK.R2.channel'),
    template: t('JRC_SERVICE_DESK.R2.template'),
    template_version: t('JRC_SERVICE_DESK.R2.template_version'),
    inbox: t('JRC_SERVICE_DESK.R2.inbox'),
    confirm_policy: t('JRC_SERVICE_DESK.R2.confirm_policy'),
    save_policy: t('JRC_SERVICE_DESK.R2.save_policy'),
    enabled: t('JRC_SERVICE_DESK.R2.enabled'),
    default_off: t('JRC_SERVICE_DESK.R2.default_off'),
    error: t('JRC_SERVICE_DESK.R2.error'),
    sla: t('JRC_SERVICE_DESK.R2.sla'),
    buttons: {
      internal: t('JRC_SERVICE_DESK.R2.buttons.internal'),
      technical_team: t('JRC_SERVICE_DESK.R2.buttons.technical_team'),
      customer: t('JRC_SERVICE_DESK.R2.buttons.customer'),
      public_without_notification: t(
        'JRC_SERVICE_DESK.R2.buttons.public_without_notification'
      ),
    },
    kinds: {
      note: t('JRC_SERVICE_DESK.R2.kinds.note'),
      event: t('JRC_SERVICE_DESK.R2.kinds.event'),
      task: t('JRC_SERVICE_DESK.R2.kinds.task'),
      approval: t('JRC_SERVICE_DESK.R2.kinds.approval'),
      message: t('JRC_SERVICE_DESK.R2.kinds.message'),
      call: t('JRC_SERVICE_DESK.R2.kinds.call'),
      delivery: t('JRC_SERVICE_DESK.R2.kinds.delivery'),
    },
    events: {
      customer_interaction: t(
        'JRC_SERVICE_DESK.R2.events.customer_interaction'
      ),
      ticket_created: t('JRC_SERVICE_DESK.R2.events.ticket_created'),
      ticket_assigned: t('JRC_SERVICE_DESK.R2.events.ticket_assigned'),
      status_changed: t('JRC_SERVICE_DESK.R2.events.status_changed'),
      waiting_customer: t('JRC_SERVICE_DESK.R2.events.waiting_customer'),
      approval_requested: t('JRC_SERVICE_DESK.R2.events.approval_requested'),
      approval_decided: t('JRC_SERVICE_DESK.R2.events.approval_decided'),
      resolved: t('JRC_SERVICE_DESK.R2.events.resolved'),
      closed: t('JRC_SERVICE_DESK.R2.events.closed'),
      reopened: t('JRC_SERVICE_DESK.R2.events.reopened'),
      task_created: t('JRC_SERVICE_DESK.R2.events.task_created'),
      task_updated: t('JRC_SERVICE_DESK.R2.events.task_updated'),
      task_completed: t('JRC_SERVICE_DESK.R2.events.task_completed'),
    },
    reasons: {
      recipient_preference: t(
        'JRC_SERVICE_DESK.R2.reasons.recipient_preference'
      ),
      authorization_revoked: t(
        'JRC_SERVICE_DESK.R2.reasons.authorization_revoked'
      ),
      visibility_not_customer: t(
        'JRC_SERVICE_DESK.R2.reasons.visibility_not_customer'
      ),
      channel_not_selected: t(
        'JRC_SERVICE_DESK.R2.reasons.channel_not_selected'
      ),
      policy_disabled: t('JRC_SERVICE_DESK.R2.reasons.policy_disabled'),
      policy_disabled_or_changed: t(
        'JRC_SERVICE_DESK.R2.reasons.policy_disabled_or_changed'
      ),
      recipient_missing: t('JRC_SERVICE_DESK.R2.reasons.recipient_missing'),
      recipient_blocked: t('JRC_SERVICE_DESK.R2.reasons.recipient_blocked'),
      conversation_not_linked: t(
        'JRC_SERVICE_DESK.R2.reasons.conversation_not_linked'
      ),
      conversation_denied: t('JRC_SERVICE_DESK.R2.reasons.conversation_denied'),
      channel_unavailable: t('JRC_SERVICE_DESK.R2.reasons.channel_unavailable'),
      smtp_unavailable: t('JRC_SERVICE_DESK.R2.reasons.smtp_unavailable'),
      recipient_changed: t('JRC_SERVICE_DESK.R2.reasons.recipient_changed'),
      event_payload_changed: t(
        'JRC_SERVICE_DESK.R2.reasons.event_payload_changed'
      ),
      no_authorized_conversation: t(
        'JRC_SERVICE_DESK.R2.reasons.no_authorized_conversation'
      ),
      message_payload_changed: t(
        'JRC_SERVICE_DESK.R2.reasons.message_payload_changed'
      ),
      incompatible_delivery_control: t(
        'JRC_SERVICE_DESK.R2.reasons.incompatible_delivery_control'
      ),
      provider_result_unknown: t(
        'JRC_SERVICE_DESK.R2.reasons.provider_result_unknown'
      ),
      provider_result_unverified: t(
        'JRC_SERVICE_DESK.R2.reasons.provider_result_unverified'
      ),
      provider_failure: t('JRC_SERVICE_DESK.R2.reasons.provider_failure'),
      previous_dispatch_result_unknown: t(
        'JRC_SERVICE_DESK.R2.reasons.previous_dispatch_result_unknown'
      ),
    },
  };
}
