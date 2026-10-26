import { canonicalId } from '../helpers/access.js';

export const STATES = [
  'open',
  'investigating',
  'in_progress',
  'waiting',
  'monitoring',
  'resolved',
  'closed',
];
export const SEVERITIES = ['low', 'normal', 'high', 'critical'];
export const EVENTS = [
  'created',
  'updated',
  'transitioned',
  'reopened',
  'tickets_linked',
  'ticket_unlinked',
  'incidents_linked',
  'incident_unlinked',
  'note_added',
  'attachment_added',
  'attachment_withdrawn',
];
export const TONES = {
  open: 'bg-n-blue-2 text-n-blue-11',
  investigating: 'bg-n-violet-2 text-n-violet-11',
  in_progress: 'bg-n-amber-2 text-n-amber-11',
  waiting: 'bg-n-ruby-2 text-n-ruby-11',
  monitoring: 'bg-n-blue-2 text-n-blue-11',
  resolved: 'bg-n-teal-2 text-n-teal-11',
  closed: 'bg-n-slate-2 text-n-slate-11',
  low: 'bg-n-teal-2 text-n-teal-11',
  normal: 'bg-n-blue-2 text-n-blue-11',
  high: 'bg-n-amber-2 text-n-amber-11',
  critical: 'bg-n-ruby-2 text-n-ruby-11',
};
const check = test => {
  if (!test) throw new TypeError('Invalid case workspace contract');
};
const object = value =>
  value !== null && typeof value === 'object' && !Array.isArray(value);
const id = value => {
  const result = canonicalId(value);
  check(!!result);
  return result;
};
const text = value => (typeof value === 'string' ? value : '');
export const clone = value => JSON.parse(JSON.stringify(value));
export const terminal = status => ['resolved', 'closed'].includes(status);
export function stable(value) {
  if (Array.isArray(value))
    return JSON.stringify(value.map(item => JSON.parse(stable(item))));
  if (object(value))
    return JSON.stringify(
      Object.fromEntries(
        Object.keys(value)
          .sort()
          .map(key => [key, JSON.parse(stable(value[key]))])
      )
    );
  return JSON.stringify(value === undefined ? null : value);
}
function named(value) {
  return value == null ? null : { id: id(value.id), name: text(value.name) };
}
export function record(value, context, kind = null) {
  check(
    object(value) &&
      value.account_id === context.account_id &&
      context.units.some(unit => unit.id === value.unit_id)
  );
  check(
    ['incident', 'problem'].includes(value.resource_kind) &&
      (!kind || value.resource_kind === kind)
  );
  check(
    STATES.includes(value.status) &&
      SEVERITIES.includes(value.severity) &&
      value.permissions?.show === true
  );
  check(
    Number.isSafeInteger(value.lock_version) &&
      value.lock_version >= 0 &&
      Array.isArray(value.allowed_transitions)
  );
  check(
    value.allowed_transitions.every(
      state => STATES.includes(state) && state !== value.status
    )
  );
  const details = {};
  [
    'hypothesis',
    'evidence_summary',
    'action_plan',
    'expected_result',
    'impact_level',
  ].forEach(key => {
    details[key] = text(value.details?.[key]);
  });
  return {
    id: id(value.id),
    account_id: context.account_id,
    unit_id: id(value.unit_id),
    resource_kind: value.resource_kind,
    code: text(value.code),
    title: text(value.title),
    description: text(value.description),
    status: value.status,
    severity: value.severity,
    impact: text(value.impact),
    cause: text(value.cause),
    workaround: text(value.workaround),
    resolution: text(value.resolution),
    details,
    service: named(value.service),
    category: named(value.category),
    unit: named(value.unit),
    operator_company: named(value.operator_company),
    owner_account_user_id: value.owner_account_user_id
      ? id(value.owner_account_user_id)
      : null,
    owner_name: text(value.owner_name),
    lock_version: value.lock_version,
    started_at: value.started_at || null,
    resolved_at: value.resolved_at || null,
    closed_at: value.closed_at || null,
    created_at: value.created_at || null,
    updated_at: value.updated_at || null,
    ticket_ids: (value.ticket_ids || []).map(id),
    related_count: value.related_count || 0,
    allowed_transitions: [...value.allowed_transitions],
    permissions: Object.fromEntries(
      ['show', 'update', 'link', 'comment', 'reopen'].map(key => [
        key,
        value.permissions[key] === true,
      ])
    ),
  };
}
export function envelope(payload, context) {
  check(
    payload?.contract_version === 1 && payload.account_id === context.account_id
  );
  return payload;
}
export function pagination(meta) {
  check(
    object(meta) &&
      ['page', 'per_page', 'total'].every(
        key =>
          Number.isSafeInteger(meta[key]) &&
          meta[key] >= (key === 'total' ? 0 : 1)
      )
  );
  return { page: meta.page, per_page: meta.per_page, total: meta.total };
}
export function list(payload, context, kind) {
  envelope(payload, context);
  check(payload.kind === kind && Array.isArray(payload.items));
  const meta = pagination(payload.meta);
  check(payload.items.length <= meta.per_page);
  const items = payload.items.map(row => record(row, context, kind));
  check(new Set(items.map(row => row.id)).size === items.length);
  const metrics = payload.metrics;
  check(
    object(metrics) &&
      [
        'total',
        'critical',
        'active',
        'resolved',
        'closed',
        'resolution_sample_size',
      ].every(key => Number.isSafeInteger(metrics[key]) && metrics[key] >= 0)
  );
  check(
    metrics.total === meta.total &&
      metrics.timezone === 'UTC' &&
      metrics.duration_basis === 'elapsed_to_last_resolution_not_sla'
  );
  check(
    metrics.resolution_average_seconds === null ||
      (Number.isFinite(metrics.resolution_average_seconds) &&
        metrics.resolution_average_seconds >= 0)
  );
  [
    ['by_status', STATES],
    ['by_severity', SEVERITIES],
  ].forEach(([key, values]) => {
    check(
      object(metrics[key]) &&
        Object.entries(metrics[key]).every(
          ([name, count]) =>
            values.includes(name) && Number.isSafeInteger(count) && count >= 0
        )
    );
    check(
      Object.values(metrics[key]).reduce((sum, n) => sum + n, 0) ===
        metrics.total
    );
  });
  return { items, meta, metrics: clone(metrics) };
}
export function formFor(row = null) {
  return {
    title: row?.title || '',
    description: row?.description || '',
    severity: row?.severity || 'normal',
    impact: row?.impact || '',
    service_id: row?.service?.id || '',
    category_id: row?.category?.id || '',
    owner_account_user_id: row?.owner_account_user_id || '',
    cause: row?.cause || '',
    workaround: row?.workaround || '',
    resolution: row?.resolution || '',
    details: {
      hypothesis: '',
      evidence_summary: '',
      action_plan: '',
      expected_result: '',
      impact_level: '',
      ...(row?.details || {}),
    },
  };
}
export function attributes(form) {
  const value = clone(form);
  check(
    typeof value.title === 'string' &&
      value.title.trim().length > 0 &&
      value.title.trim().length <= 255
  );
  check(SEVERITIES.includes(value.severity));
  value.title = value.title.trim();
  ['service_id', 'category_id', 'owner_account_user_id'].forEach(key => {
    value[key] = value[key] ? id(value[key]) : null;
  });
  Object.keys(value.details).forEach(key => {
    if (value.details[key] === '') value.details[key] = null;
  });
  return value;
}
export function selectItem(selected, item, checked, limit = 100) {
  const next = new Map(selected.map(row => [row.id, row]));
  if (checked) {
    check(!item.linked && item.selectable !== false);
    next.set(id(item.id), item);
  } else next.delete(id(item.id));
  if (next.size > limit) throw new RangeError('Selection limit exceeded');
  return [...next.values()];
}
export function mayDrop(row, target) {
  return (
    !!row &&
    row.permissions?.show === true &&
    row.allowed_transitions?.includes(target) === true
  );
}
export function formatElapsed(seconds) {
  if (!Number.isFinite(seconds) || seconds < 0) return null;
  const minutes = Math.round(seconds / 60);
  return minutes < 60
    ? `${minutes} min`
    : `${Math.floor(minutes / 60)} h ${minutes % 60} min`;
}
export function safeError(error, fallback) {
  const status = error?.response?.status;
  if (status === 401 || status === 403)
    return { kind: 'denied', message: fallback.denied };
  if (status === 409) return { kind: 'conflict', message: fallback.conflict };
  const message = error?.response?.data?.error;
  if (status === 422 && typeof message === 'string' && message.length < 400)
    return { kind: 'invalid', message };
  return { kind: 'uncertain', message: fallback.uncertain };
}
