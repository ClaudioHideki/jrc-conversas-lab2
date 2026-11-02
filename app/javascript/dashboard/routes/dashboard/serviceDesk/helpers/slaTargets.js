export const durationUnits = Object.freeze({
  seconds: 1,
  minutes: 60,
  hours: 3600,
});
export function durationSeconds(value, unit) {
  if (
    !Object.hasOwn(durationUnits, unit) ||
    !/^\d+(\.\d+)?$/.test(String(value))
  )
    throw new TypeError('Invalid SLA duration');
  const seconds = Number(value) * durationUnits[unit];
  if (!Number.isSafeInteger(seconds) || seconds <= 0)
    throw new TypeError('SLA requires positive whole seconds');
  return seconds;
}
export function targetBudgets(policy) {
  const budgets = policy.clock_budgets_seconds;
  if (
    !budgets ||
    typeof budgets !== 'object' ||
    Array.isArray(budgets) ||
    !['first_response', 'resolution'].every(key =>
      Object.hasOwn(budgets, key)
    ) ||
    Object.keys(budgets).some(
      key => !['first_response', 'attendance', 'resolution'].includes(key)
    ) ||
    Object.values(budgets).some(
      value => !Number.isSafeInteger(value) || value <= 0
    )
  )
    throw new TypeError('Incomplete SLA targets');
  return budgets;
}
export function closureConfiguration(raw, choice) {
  const draft = JSON.parse(raw);
  if (!draft?.sla || !['strict', 'operational', 'contractual'].includes(choice))
    throw new TypeError('Invalid closure configuration');
  delete draft.sla.obligation;
  delete draft.sla.missing_configuration;
  if (choice !== 'strict') {
    draft.sla.obligation = choice;
    draft.sla.missing_configuration =
      choice === 'operational' ? 'allow_operational_closure' : 'block';
  }
  return JSON.stringify(draft, null, 2);
}
