export function playbookFlowLabels(t) {
  const labels = {
    playbook_flow_effects_disabled: t(
      'RELATIONSHIP.FLOW_REASONS.effects_disabled'
    ),
    playbook_flow_phase_not_approved: t(
      'RELATIONSHIP.FLOW_REASONS.phase_not_approved'
    ),
    playbook_flow_company_not_in_pilot: t(
      'RELATIONSHIP.FLOW_REASONS.company_not_in_pilot'
    ),
    playbook_flow_actor_not_in_pilot: t(
      'RELATIONSHIP.FLOW_REASONS.actor_not_in_pilot'
    ),
    playbook_flow_unit_not_in_pilot: t(
      'RELATIONSHIP.FLOW_REASONS.unit_not_in_pilot'
    ),
    explicit_flow_approval_required: t(
      'RELATIONSHIP.FLOW_REASONS.approval_required'
    ),
    playbook_flow_approval_invalid_or_expired: t(
      'RELATIONSHIP.FLOW_REASONS.approval_expired'
    ),
    playbook_flow_approval_expired: t(
      'RELATIONSHIP.FLOW_REASONS.approval_expired'
    ),
    playbook_flow_approval_binding_changed: t(
      'RELATIONSHIP.FLOW_REASONS.approval_changed'
    ),
    playbook_flow_hourly_limit: t('RELATIONSHIP.FLOW_REASONS.hourly_limit'),
    playbook_flow_native_origin_required: t(
      'RELATIONSHIP.FLOW_REASONS.origin_required'
    ),
    native_conversation_live_run_exists: t(
      'RELATIONSHIP.FLOW_REASONS.live_run'
    ),
    native_run_requires_review: t('RELATIONSHIP.FLOW_REASONS.native_review'),
    playbook_flow_effect_not_approved: t(
      'RELATIONSHIP.FLOW_REASONS.effect_not_approved'
    ),
    remote_flow_simulator_and_relationship_guard_unavailable: t(
      'RELATIONSHIP.FLOW_REASONS.remote_unavailable'
    ),
    workflow_relationship_continuation_guard_required: t(
      'RELATIONSHIP.FLOW_REASONS.engine_unavailable'
    ),
    native_manual_trigger_required: t(
      'RELATIONSHIP.FLOW_REASONS.manual_required'
    ),
    native_message_keyword_input_required: t(
      'RELATIONSHIP.FLOW_REASONS.keyword_unavailable'
    ),
    native_dispatch_business_hours_guard_required: t(
      'RELATIONSHIP.FLOW_REASONS.hours_unavailable'
    ),
    native_relationship_delivery_guard_required: t(
      'RELATIONSHIP.FLOW_REASONS.delivery_unavailable'
    ),
    native_relationship_action_grants_required: t(
      'RELATIONSHIP.FLOW_REASONS.action_unavailable'
    ),
    handoff_acceptance_required: t(
      'RELATIONSHIP.FLOW_REASONS.handoff_required'
    ),
    conditions_not_matched: t(
      'RELATIONSHIP.FLOW_REASONS.conditions_not_matched'
    ),
    playbook_not_eligible: t(
      'RELATIONSHIP.FLOW_REASONS.conditions_not_matched'
    ),
    native_permission_unavailable: t(
      'RELATIONSHIP.FLOW_REASONS.permission_unavailable'
    ),
  };
  const fallback = t('RELATIONSHIP.FLOW_REASONS.blocked');
  return reason =>
    reason ? labels[String(reason).split(':')[0]] || fallback : '';
}
