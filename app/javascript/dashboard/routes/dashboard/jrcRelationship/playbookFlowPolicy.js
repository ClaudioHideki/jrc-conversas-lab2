export const flowMutationEffects = Object.freeze([
  'status',
  'labels',
  'assign',
  'contact_update',
  'create_lead',
  'activity',
  'move_deal',
  'media',
  'webhook',
  'nico',
]);
const effects = ['note', 'message', ...flowMutationEffects];
const ranges = {
  phase: [1, 3],
  approved_phase: [0, 3],
  approval_ttl_seconds: [30, 900],
  hourly_limit: [1, 1000],
  max_steps: [1, 200],
};
const pilots = [
  'pilot_company_ids',
  'pilot_business_unit_ids',
  'pilot_account_user_ids',
];
const flags = ['allow_unassigned_business_unit', 'approval_required'];
const keys = [...Object.keys(ranges), ...pilots, ...flags, 'allowed_effects'];

// Decoding a native policy does not grant execution or approve a phase.
export function isPlaybookFlowPolicy(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  if (
    Object.keys(value).length !== keys.length ||
    keys.some(key => !Object.hasOwn(value, key))
  )
    return false;
  if (
    !Object.entries(ranges).every(
      ([key, [min, max]]) =>
        Number.isSafeInteger(value[key]) &&
        value[key] >= min &&
        value[key] <= max
    )
  )
    return false;
  if (
    !pilots.every(
      key =>
        Array.isArray(value[key]) &&
        value[key].every(id => Number.isSafeInteger(id) && id > 0) &&
        new Set(value[key]).size === value[key].length
    )
  )
    return false;
  if (!flags.every(key => typeof value[key] === 'boolean')) return false;
  return (
    Array.isArray(value.allowed_effects) &&
    new Set(value.allowed_effects).size === value.allowed_effects.length &&
    value.allowed_effects.every(effect => effects.includes(effect))
  );
}

export function reviewedFlowEffects(policy, effect, enabled) {
  if (
    !isPlaybookFlowPolicy(policy) ||
    !effects.includes(effect) ||
    typeof enabled !== 'boolean'
  )
    return null;
  if (
    enabled &&
    flowMutationEffects.includes(effect) &&
    (policy.phase !== 3 || policy.approved_phase !== 3)
  )
    return null;
  const current = policy.allowed_effects.filter(value => value !== effect);
  return enabled ? [...current, effect] : current;
}
