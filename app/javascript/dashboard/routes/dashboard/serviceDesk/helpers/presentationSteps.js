export const CATALOG_STEPS = Object.freeze([
  'information',
  'categorization',
  'rules',
  'form',
  'permissions',
  'publication',
]);
export const POLICY_STEPS = Object.freeze([
  'general',
  'lifecycle',
  'monitoring',
  'routing',
  'notifications',
  'review',
]);
export const NOTIFICATION_STEPS = Object.freeze([
  'general',
  'conditions',
  'channels',
  'message',
  'preview',
  'review',
]);
export function nextStep(steps, current, offset = 1) {
  const index = steps.indexOf(current);
  return steps[
    Math.max(0, Math.min(steps.length - 1, (index < 0 ? 0 : index) + offset))
  ];
}
export function serviceFieldSection(field) {
  if (['name', 'code', 'description', 'position'].includes(field))
    return 'information';
  if (['default_category_id', 'default_ticket_type_id'].includes(field))
    return 'categorization';
  if (
    [
      'default_priority_id',
      'default_queue_id',
      'default_assignee_membership_id',
      'approval_required',
    ].includes(field)
  )
    return 'rules';
  if (field === 'form_fields') return 'form';
  if (
    [
      'allowed_company_ids',
      'allowed_contract_ids',
      'portal_history_days',
      'portal_access_until',
    ].includes(field)
  )
    return 'permissions';
  return 'publication';
}
