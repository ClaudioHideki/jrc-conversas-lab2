// Draft editing only. Publication, authority and transition validation remain in Rails.
const object = value =>
  value !== null && typeof value === 'object' && !Array.isArray(value);
const forbidden = ['__proto__', 'prototype', 'constructor'];
export const ACTIONS = Object.freeze([
  'pause',
  'resume',
  'resolve',
  'close',
  'cancel',
  'reopen',
  'work_status',
]);
export function readLifecycleDraft(raw) {
  try {
    const value = JSON.parse(raw);
    if (
      !value ||
      ![1, 2].includes(value.schema_version) ||
      !Array.isArray(value.transitions) ||
      !Array.isArray(value.pause_reasons) ||
      !object(value.sla) ||
      !object(value.reopen)
    )
      return null;
    if (
      !value.transitions.every(
        row =>
          object(row) &&
          typeof row.key === 'string' &&
          typeof row.action === 'string' &&
          Array.isArray(row.from_status_ids) &&
          object(row.clocks) &&
          object(row.requirements) &&
          object(row.requirements.fields)
      ) ||
      !value.pause_reasons.every(
        row =>
          object(row) &&
          typeof row.code === 'string' &&
          typeof row.name === 'string' &&
          Array.isArray(row.status_ids) &&
          Array.isArray(row.clocks)
      )
    )
      return null;
    return value;
  } catch {
    return null;
  }
}
export function clockKinds(definition) {
  return definition.schema_version === 2
    ? ['first_response', 'attendance', 'resolution']
    : ['first_response', 'resolution'];
}
export function blankLifecycleDraft() {
  return JSON.stringify(
    {
      schema_version: 2,
      transitions: [],
      pause_reasons: [],
      reopen: {
        allowed: false,
        window_seconds: null,
        anchor_action: null,
        expired: null,
        sla_cycle: null,
        inactive_time: null,
        resume_clocks: [],
        new_cycle_snapshot: null,
      },
      sla: { mode: '', initial_start: 'opened_at', escalation_policy: {} },
    },
    null,
    2
  );
}
export function blankTransition(definition) {
  return {
    key: '',
    action: '',
    from_status_ids: [],
    to_status_id: null,
    requirements: {
      note: false,
      solution: false,
      evidence: false,
      classification: false,
      fields: {},
    },
    clocks: Object.fromEntries(
      clockKinds(definition).map(key => [key, 'keep'])
    ),
    end_pause: false,
  };
}
export function explicitInteger(value) {
  if (value === '' || value === null) return null;
  if (!/^[1-9][0-9]*$/.test(String(value)))
    throw new TypeError('Explicit positive integer required');
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) throw new TypeError('Unsafe integer');
  return parsed;
}
export function patchLifecycleDraft(raw, path, value) {
  const draft = readLifecycleDraft(raw);
  if (
    !draft ||
    !Array.isArray(path) ||
    !path.length ||
    path.length > 8 ||
    path.some(key => forbidden.includes(String(key)))
  )
    throw new TypeError('Invalid draft path');
  let cursor = draft;
  Array.from(path.slice(0, -1)).forEach(key => {
    if (!cursor || typeof cursor !== 'object' || !Object.hasOwn(cursor, key))
      throw new TypeError('Unknown draft path');
    cursor = cursor[key];
  });
  const key = path[path.length - 1];
  if (!cursor || typeof cursor !== 'object' || !Object.hasOwn(cursor, key))
    throw new TypeError('Unknown draft field');
  cursor[key] = value;
  return JSON.stringify(draft, null, 2);
}
const token = value =>
  typeof value === 'string' &&
  /^[a-zA-Z0-9_.-]{1,80}$/.test(value) &&
  !forbidden.includes(value);
const positive = value => Number.isSafeInteger(value) && value > 0;
// Advisory checks deliberately do NOT establish permission or backend publishability.
export function lifecycleDraftIssues(raw) {
  const d = readLifecycleDraft(raw);
  if (!d) return ['format'];
  const issues = new Set();
  if (
    !['not_applicable', 'calendar_snapshot'].includes(d.sla.mode) ||
    d.sla.initial_start !== 'opened_at'
  )
    issues.add('mode');
  if (!d.transitions.length || d.transitions.length > 100)
    issues.add('transitions');
  if (new Set(d.transitions.map(row => row?.key)).size !== d.transitions.length)
    issues.add('duplicates');
  const kinds = clockKinds(d);
  Array.from(d.transitions).forEach(row => {
    if (!row || !token(row.key) || !ACTIONS.includes(row.action)) {
      issues.add('transitions');
      return;
    }
    if (
      !Array.isArray(row.from_status_ids) ||
      !row.from_status_ids.length ||
      row.from_status_ids.length > 100 ||
      !row.from_status_ids.every(positive) ||
      new Set(row.from_status_ids).size !== row.from_status_ids.length ||
      !positive(row.to_status_id)
    )
      issues.add('states');
    if (
      typeof row.end_pause !== 'boolean' ||
      !row.requirements ||
      !['note', 'solution', 'evidence', 'classification'].every(
        key => typeof row.requirements[key] === 'boolean'
      )
    )
      issues.add('fields');
    const clocks = row.clocks;
    if (
      !clocks ||
      Object.keys(clocks).sort().join() !== [...kinds].sort().join() ||
      !Object.values(clocks).every(value =>
        ['keep', 'stop', 'complete'].includes(value)
      )
    ) {
      issues.add('clocks');
      return;
    }
    if (
      clocks.first_response === 'complete' ||
      (clocks.resolution === 'complete' && row.action !== 'resolve') ||
      (clocks.attendance === 'complete' &&
        !['work_status', 'resolve'].includes(row.action))
    )
      issues.add('clocks');
    if (
      d.sla.mode === 'not_applicable' &&
      Object.values(clocks).some(value => value !== 'keep')
    )
      issues.add('clocks');
    if (
      ['pause', 'resume', 'reopen', 'work_status'].includes(row.action) &&
      kinds
        .filter(key => row.action !== 'work_status' || key !== 'attendance')
        .some(key => clocks[key] !== 'keep')
    )
      issues.add('clocks');
  });
  if (
    d.pause_reasons.length > 100 ||
    new Set(d.pause_reasons.map(row => row?.code)).size !==
      d.pause_reasons.length
  )
    issues.add('duplicates');
  d.pause_reasons.forEach(row => {
    if (
      !row ||
      !token(row.code) ||
      !row.name ||
      !Array.isArray(row.status_ids) ||
      !row.status_ids.length ||
      !row.status_ids.every(positive) ||
      !Array.isArray(row.clocks) ||
      row.clocks.some(key => !kinds.includes(key)) ||
      (d.sla.mode === 'not_applicable' && row.clocks.length)
    )
      issues.add('pauses');
  });
  if (typeof d.reopen.allowed !== 'boolean') issues.add('reopen');
  if (
    d.reopen.allowed &&
    (!positive(d.reopen.window_seconds) ||
      !['resolve', 'close', 'cancel'].includes(d.reopen.anchor_action) ||
      !['deny', 'require_new_ticket'].includes(d.reopen.expired) ||
      !['continue_cycle', 'new_cycle'].includes(d.reopen.sla_cycle) ||
      !['count', 'exclude'].includes(d.reopen.inactive_time) ||
      !['same_snapshot', 'latest_snapshot'].includes(
        d.reopen.new_cycle_snapshot
      ) ||
      !Array.isArray(d.reopen.resume_clocks) ||
      d.reopen.resume_clocks.some(key => !kinds.includes(key)))
  )
    issues.add('reopen');
  return [...issues];
}
export function simulateLifecycleDraft(raw, stateId) {
  const d = readLifecycleDraft(raw);
  const state = explicitInteger(stateId);
  if (!d || !state || lifecycleDraftIssues(raw).length) return [];
  return d.transitions
    .filter(row => row.from_status_ids.includes(state))
    .map(row => ({
      key: row.key,
      action: row.action,
      to_status_id: row.to_status_id,
      requirements: JSON.parse(JSON.stringify(row.requirements)),
      clocks: { ...row.clocks },
    }));
}
