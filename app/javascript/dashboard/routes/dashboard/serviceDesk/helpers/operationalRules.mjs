import { canonicalId } from './access.js';

export const ruleKinds = Object.freeze([
  'routing',
  'priority_matrix',
  'sla_selection',
  'approval_deadline',
  'recurrence',
]);
export const predicateFields = Object.freeze([
  'inbox_id',
  'channel_type',
  'company_id',
  'contract_id',
  'category_id',
  'service_id',
  'priority_id',
  'ticket_type_id',
  'impact',
  'urgency',
]);
export const snapshotTextFields = Object.freeze([
  'source_system',
  'source_reference',
  'source_version',
  'policy_key',
  'policy_version',
  'calendar_key',
  'calendar_version',
  'calendar_scope',
  'timezone',
]);
export const snapshotObjectFields = Object.freeze([
  'contract_conditions',
  'policy_conditions',
  'calendar_conditions',
]);
export const groupingFields = Object.freeze([
  'company_id',
  'service_id',
  'category_id',
  'ticket_type_id',
  'normalized_title',
]);
export const approvalTargets = Object.freeze([
  'approver_account_user_id',
  'approver_team_id',
  'approver_role',
  'approver_custom_role_id',
]);
export const kindLabels = Object.freeze({
  routing: 'JRC_SERVICE_DESK.COMPLETION.kinds.routing',
  priority_matrix: 'JRC_SERVICE_DESK.COMPLETION.kinds.priority_matrix',
  sla_selection: 'JRC_SERVICE_DESK.COMPLETION.kinds.sla_selection',
  approval_deadline: 'JRC_SERVICE_DESK.COMPLETION.kinds.approval_deadline',
  recurrence: 'JRC_SERVICE_DESK.COMPLETION.kinds.recurrence',
});
const assert = value => {
  if (!value) throw new TypeError('Invalid operational configuration');
};
export const jsonObject = text => {
  const value = JSON.parse(text);
  assert(value !== null && typeof value === 'object' && !Array.isArray(value));
  const check = (item, depth = 0) => {
    assert(depth <= 24);
    if (item && typeof item === 'object') {
      Object.entries(item).forEach(([key, child]) => {
        assert(!['__proto__', 'prototype', 'constructor'].includes(key));
        assert(
          !/password|secret|credential|access_token|refresh_token|api_key|authorization/i.test(
            key
          )
        );
        check(child, depth + 1);
      });
    }
    if (typeof item === 'number') assert(Number.isFinite(item));
  };
  check(value);
  return value;
};
export function integer(value, minimum = 1, maximum = Number.MAX_SAFE_INTEGER) {
  assert(typeof value === 'string' || typeof value === 'number');
  assert(/^(0|[1-9][0-9]*)$/.test(String(value)));
  const result = Number(value);
  assert(
    Number.isSafeInteger(result) && result >= minimum && result <= maximum
  );
  return result;
}
export function code(value) {
  assert(
    typeof value === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$/.test(value)
  );
  return value;
}
export function emptyRule() {
  return { key: '', precedence: '', match: {}, target: '', snapshot: {} };
}
export function rulesDefinition(kind, rows) {
  assert(
    ['routing', 'priority_matrix', 'sla_selection'].includes(kind) &&
      Array.isArray(rows) &&
      rows.length >= 1 &&
      rows.length <= 100
  );
  const rules = rows.map(row => {
    const match = {};
    predicateFields.forEach(field => {
      const value = row.match[field];
      if (value === undefined || value === null || value === '') return;
      if (field.endsWith('_id')) match[field] = integer(value);
      else if (field === 'channel_type') {
        assert(/^Channel::[A-Za-z][A-Za-z0-9]{0,60}$/.test(value));
        match[field] = value;
      } else match[field] = code(value);
    });
    if (kind === 'priority_matrix') assert(match.impact && match.urgency);
    let output;
    if (kind === 'sla_selection') {
      const snapshot = {};
      snapshotTextFields.forEach(field => {
        assert(
          typeof row.snapshot[field] === 'string' &&
            row.snapshot[field].trim().length > 0
        );
        snapshot[field] = row.snapshot[field];
      });
      snapshotObjectFields.forEach(field => {
        snapshot[field] = jsonObject(row.snapshot[field]);
      });
      output = { snapshot };
    } else
      output = {
        [kind === 'routing' ? 'queue_id' : 'priority_id']: integer(row.target),
      };
    return {
      key: code(row.key),
      precedence: integer(row.precedence, 0, 1000000),
      match,
      output,
    };
  });
  assert(new Set(rules.map(row => row.key)).size === rules.length);
  return { rules };
}
export function loadRules(definition) {
  return (definition?.rules || []).map(row => ({
    key: row.key,
    precedence: String(row.precedence),
    match: { ...row.match },
    target: String(row.output.queue_id || row.output.priority_id || ''),
    snapshot: row.output.snapshot
      ? Object.fromEntries(
          Object.entries(row.output.snapshot).map(([key, value]) => [
            key,
            snapshotObjectFields.includes(key)
              ? JSON.stringify(value, null, 2)
              : value,
          ])
        )
      : {},
  }));
}
export function deadlineDefinition(draft) {
  assert(approvalTargets.includes(draft.target_kind));
  const target =
    draft.target_kind === 'approver_role'
      ? draft.target_value
      : integer(draft.target_value);
  if (draft.target_kind === 'approver_role')
    assert(['agent', 'administrator'].includes(target));
  assert(
    typeof draft.reason === 'string' &&
      draft.reason.trim().length >= 1 &&
      draft.reason.length <= 1000
  );
  return {
    executor_account_user_id: integer(draft.executor_account_user_id),
    after_due_seconds: integer(draft.after_due_seconds, 0, 31536000),
    new_due_seconds: integer(draft.new_due_seconds, 1, 31536000),
    target: { [draft.target_kind]: target },
    reason: draft.reason,
  };
}
export function recurrenceDefinition(draft) {
  assert(
    Array.isArray(draft.group_by) &&
      draft.group_by.length > 0 &&
      draft.group_by.every(key => groupingFields.includes(key))
  );
  assert(new Set(draft.group_by).size === draft.group_by.length);
  return {
    window_days: integer(draft.window_days, 1, 366),
    minimum_occurrences: integer(draft.minimum_occurrences, 2, 1000),
    group_by: [...draft.group_by],
  };
}
export function assertEnvelope(payload, context, unit) {
  assert(
    payload &&
      payload.contract_version === 1 &&
      canonicalId(payload.account_id) === context.account_id &&
      canonicalId(payload.unit_id) === canonicalId(unit)
  );
  assert(context.units.some(row => row.id === canonicalId(unit)));
  return payload;
}
export function reportFilters(values) {
  const result = {};
  const allowed = [
    'service_id',
    'company_id',
    'inbox_id',
    'channel_type',
    'category_id',
    'priority_id',
    'from',
    'to',
    'page',
    'per_page',
  ];
  assert(Object.keys(values).every(key => allowed.includes(key)));
  Object.entries(values).forEach(([key, value]) => {
    if (value === '' || value === null || value === undefined) return;
    if (key.endsWith('_id')) {
      assert(canonicalId(value));
      result[key] = canonicalId(value);
    } else if (key === 'page' || key === 'per_page')
      result[key] = integer(value, 1, key === 'page' ? 1000000 : 100);
    else if (key === 'channel_type') {
      assert(/^Channel::[A-Za-z][A-Za-z0-9]{0,60}$/.test(value));
      result[key] = value;
    } else {
      assert(
        typeof value === 'string' &&
          /(?:Z|[+-]\d{2}:\d{2})$/.test(value) &&
          Number.isFinite(Date.parse(value))
      );
      result[key] = value;
    }
  });
  if (result.from && result.to)
    assert(Date.parse(result.from) < Date.parse(result.to));
  return result;
}
