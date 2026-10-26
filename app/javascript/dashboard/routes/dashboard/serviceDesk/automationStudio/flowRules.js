// Pure presentation contracts. Server authorization remains authoritative.
export const OLA_STEPS = [
  'information',
  'distribution',
  'deadlines',
  'escalation',
  'monitoring',
  'review',
];
export const NOTIFICATION_STEPS = [
  'information',
  'events',
  'message',
  'permissions',
  'review',
];
export const CLOSURE_STEPS = [
  'information',
  'policies',
  'tickets',
  'validation',
  'preview',
  'execution',
];
export const MAX_REVISION_ITEMS = 100;
export function selectedPage(current, rows, limit = MAX_REVISION_ITEMS) {
  const values = [
    ...new Set([
      ...current,
      ...rows.filter(row => !row.reason).map(row => String(row.id)),
    ]),
  ];
  if (values.length > limit)
    return { ok: false, selected: [...current], reason: 'selection_limit' };
  return { ok: true, selected: values };
}
export function previewCurrent(preview, now = Date.now()) {
  return (
    !!preview?.receipt &&
    Number.isFinite(Date.parse(preview.expires_at)) &&
    Date.parse(preview.expires_at) > now
  );
}
export function secondsFor(value, unit) {
  if (!['minutes', 'hours'].includes(unit) || String(value).trim() === '')
    return null;
  const duration = Number(value) * (unit === 'hours' ? 3600 : 60);
  return Number.isSafeInteger(duration) &&
    duration > 0 &&
    duration <= 2147483647
    ? duration
    : null;
}
export function displayDuration(seconds) {
  if (!Number.isSafeInteger(seconds) || seconds <= 0)
    return { value: '', unit: 'minutes' };
  return seconds % 3600 === 0
    ? { value: seconds / 3600, unit: 'hours' }
    : { value: seconds / 60, unit: 'minutes' };
}
export function validThresholds(policy) {
  if (!policy || Object.keys(policy).length === 0) return true;
  const rows = policy.thresholds;
  return (
    Array.isArray(rows) &&
    rows.length > 0 &&
    rows.length <= 20 &&
    rows.every(
      (row, i) =>
        Number.isInteger(row.percent) &&
        row.percent >= 1 &&
        row.percent <= 100 &&
        (i === 0 || row.percent > rows[i - 1].percent) &&
        (!row.team_id || !!row.queue_id)
    ) &&
    (!policy.automatic ||
      (policy.enabled && !!policy.execution_account_user_id))
  );
}
export function snapshot(value) {
  return JSON.parse(JSON.stringify(value));
}
export function draftKey(kind, context, unitId, record = 'new') {
  if (
    ![context?.account_id, context?.user_id, unitId].every(value =>
      /^\d+$/.test(String(value))
    )
  )
    return null;
  return `jrc:sd:automation-studio:v1:${context.account_id}:${context.user_id}:${unitId}:${kind}:${record}`;
}
export function writeDraft(storage, key, value, revision) {
  if (!key) throw new TypeError('Explicit draft scope required');
  storage.setItem(
    key,
    JSON.stringify({
      format: 1,
      revision: revision || null,
      value,
      saved_at: new Date().toISOString(),
    })
  );
}
export function readDraft(storage, key, revision) {
  if (!key) throw new TypeError('Explicit draft scope required');
  const draft = JSON.parse(storage.getItem(key));
  if (
    !draft ||
    draft.format !== 1 ||
    !draft.value ||
    typeof draft.value !== 'object'
  )
    throw new TypeError('Draft unavailable');
  if (draft.revision !== (revision || null))
    throw new TypeError('Draft revision changed');
  return snapshot(draft.value);
}
export function policyIdentity(policy) {
  return JSON.stringify([
    policy.event_type,
    policy.channel,
    policy.ticket_type_id || null,
    policy.service_id || null,
  ]);
}
export function latestPolicies(rows) {
  const selected = new Map();
  rows.forEach(row => {
    const key = policyIdentity(row);
    if (
      !selected.has(key) ||
      Number(row.version) > Number(selected.get(key).version)
    )
      selected.set(key, row);
  });
  return [...selected.values()];
}
export function batchProgress(result) {
  const rows = result?.results || [];
  const counts = { applied: 0, blocked: 0, conflict: 0, pending: 0 };
  rows.forEach(row => {
    if (Object.hasOwn(counts, row.status)) counts[row.status] += 1;
  });
  return {
    ...counts,
    total: rows.length,
    finished: rows.length - counts.pending,
  };
}
export function sameJSON(a, b) {
  if (a === b) return true;
  if (
    !a ||
    !b ||
    typeof a !== 'object' ||
    typeof b !== 'object' ||
    Array.isArray(a) !== Array.isArray(b)
  )
    return false;
  const keys = Object.keys(a);
  return (
    keys.length === Object.keys(b).length &&
    keys.every(key => Object.hasOwn(b, key) && sameJSON(a[key], b[key]))
  );
}
