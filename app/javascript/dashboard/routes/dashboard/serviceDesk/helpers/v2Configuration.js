import { canonicalId } from './access';
import { catalogueFields } from './catalogueFields';

export const DISTRIBUTION_MODES = [
  'manual',
  'round_robin',
  'least_load',
  'skill',
  'priority_sla',
];
export const AVAILABILITY_STATES = ['unavailable', 'available', 'paused'];
const fields = {
  queues: [
    'distribution_mode',
    'required_skills',
    'ola_budget_seconds',
    'ola_time_basis',
    'ola_pause_waiting',
    'ola_escalation_policy',
  ],
  categories: ['parent_id', 'form_fields'],
  ticket_types: ['form_fields'],
  services: [
    'description',
    'form_fields',
    'default_priority_id',
    'default_queue_id',
    'approval_required',
    'portal_enabled',
    'portal_inbox_id',
    'portal_execution_membership_id',
    'default_category_id',
    'default_ticket_type_id',
    'default_assignee_membership_id',
    'allowed_company_ids',
    'allowed_contract_ids',
    'portal_history_days',
    'portal_access_until',
  ],
};
export const configurationV2Fields = resource => fields[resource] || [];
export const membershipV2Fields = ['availability', 'capacity', 'skills'];
const check = value => {
  if (!value) throw new TypeError('Invalid operational setting');
};
export function canonicalIds(value) {
  check(Array.isArray(value) && value.length <= 100);
  const ids = value.map(item => canonicalId(item));
  check(ids.every(Boolean) && new Set(ids).size === ids.length);
  return ids;
}
export function escalationPolicy(value) {
  check(value && typeof value === 'object' && !Array.isArray(value));
  const keys = Object.keys(value);
  if (!keys.length) return {};
  check(
    keys.includes('enabled') &&
      keys.includes('thresholds') &&
      keys.every(key =>
        [
          'enabled',
          'thresholds',
          'automatic',
          'execution_account_user_id',
        ].includes(key)
      )
  );
  check(typeof value.enabled === 'boolean' && Array.isArray(value.thresholds));
  check(value.thresholds.length >= 1 && value.thresholds.length <= 20);
  const thresholds = value.thresholds.map(row => {
    check(
      row &&
        Object.keys(row).length === 3 &&
        ['percent', 'queue_id', 'team_id'].every(key => Object.hasOwn(row, key))
    );
    check(
      Number.isInteger(row.percent) && row.percent >= 1 && row.percent <= 100
    );
    const queue = row.queue_id === null ? null : canonicalId(row.queue_id);
    const team = row.team_id === null ? null : canonicalId(row.team_id);
    check(
      (row.queue_id === null || queue) &&
        (row.team_id === null || team) &&
        (!team || queue)
    );
    return { percent: row.percent, queue_id: queue, team_id: team };
  });
  check(new Set(thresholds.map(row => row.percent)).size === thresholds.length);
  const result = { enabled: value.enabled, thresholds };
  if (Object.hasOwn(value, 'automatic')) {
    check(typeof value.automatic === 'boolean');
    result.automatic = value.automatic;
  }
  if (Object.hasOwn(value, 'execution_account_user_id')) {
    result.execution_account_user_id =
      value.execution_account_user_id === null
        ? null
        : canonicalId(value.execution_account_user_id);
    check(
      result.execution_account_user_id ||
        value.execution_account_user_id === null
    );
  }
  check(
    value.automatic !== true ||
      (value.enabled && result.execution_account_user_id)
  );
  return result;
}
export function skillCodes(value) {
  check(
    Array.isArray(value) &&
      value.length <= 50 &&
      new Set(value).size === value.length
  );
  check(
    value.every(
      item => typeof item === 'string' && /^[A-Za-z0-9_.-]{1,80}$/.test(item)
    )
  );
  return [...value];
}
export function settingAttributes(data) {
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => {
      if (key.endsWith('_id')) {
        value = value === null ? null : canonicalId(value);
        check(value !== null || data[key] === null);
      }
      if (key === 'distribution_mode')
        check(DISTRIBUTION_MODES.includes(value));
      if (key === 'availability') check(AVAILABILITY_STATES.includes(value));
      if (['required_skills', 'skills'].includes(key))
        value = skillCodes(value);
      if (key === 'form_fields') value = catalogueFields(value);
      if (['allowed_company_ids', 'allowed_contract_ids'].includes(key))
        value = canonicalIds(value);
      if (key === 'ola_escalation_policy') value = escalationPolicy(value);
      if (
        ['ola_pause_waiting', 'approval_required', 'portal_enabled'].includes(
          key
        )
      )
        check(typeof value === 'boolean');
      if (['ola_budget_seconds', 'portal_history_days'].includes(key))
        check(value === null || (Number.isSafeInteger(value) && value > 0));
      if (key === 'capacity')
        check(
          value === null ||
            (Number.isInteger(value) && value > 0 && value <= 1000)
        );
      if (key === 'ola_time_basis')
        check(value === null || ['business', 'calendar'].includes(value));
      if (key === 'description')
        check(
          value === null || (typeof value === 'string' && value.length <= 20000)
        );
      if (key === 'portal_access_until') {
        check(
          value === null ||
            (typeof value === 'string' &&
              /^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(value) &&
              Number.isFinite(Date.parse(value)))
        );
        if (value !== null) {
          const fraction = (
            value.match(/\.(\d+)(?:Z|[+-]\d{2}:\d{2})$/)?.[1] || ''
          )
            .slice(0, 6)
            .padEnd(6, '0');
          value = new Date(value)
            .toISOString()
            .replace(/\.\d{3}Z$/, `.${fraction}Z`);
        }
      }
      return [key, value];
    })
  );
}
export function sameSetting(left, right) {
  if (left === right) return true;
  if (
    left === null ||
    right === null ||
    typeof left !== 'object' ||
    typeof right !== 'object'
  )
    return false;
  if (Array.isArray(left) !== Array.isArray(right)) return false;
  const keys = Object.keys(left);
  return (
    keys.length === Object.keys(right).length &&
    keys.every(
      key => Object.hasOwn(right, key) && sameSetting(left[key], right[key])
    )
  );
}
export function operationalDefaults(resource) {
  if (resource === 'queues')
    return {
      distribution_mode: 'manual',
      required_skills: [],
      ola_budget_seconds: null,
      ola_time_basis: null,
      ola_pause_waiting: false,
      ola_escalation_policy: {},
    };
  if (resource === 'categories') return { parent_id: null, form_fields: [] };
  if (resource === 'ticket_types') return { form_fields: [] };
  if (resource === 'services')
    return {
      description: '',
      form_fields: [],
      default_priority_id: null,
      default_queue_id: null,
      approval_required: false,
      portal_enabled: false,
      portal_inbox_id: null,
      portal_execution_membership_id: null,
      default_category_id: null,
      default_ticket_type_id: null,
      default_assignee_membership_id: null,
      allowed_company_ids: [],
      allowed_contract_ids: [],
      portal_history_days: null,
      portal_access_until: null,
    };
  return {};
}
export function portalOptions(payload, context, unitId) {
  check(
    payload?.contract_version === 1 &&
      payload.account_id === context.account_id &&
      payload.unit_id === unitId
  );
  check(
    context.units.some(unit => unit.id === unitId) &&
      context.capabilities?.configuration?.services === true
  );
  const rows = (name, inbox = false) => {
    check(Array.isArray(payload[name]));
    const list = payload[name].map(row => {
      const id = canonicalId(row.id);
      check(
        id &&
          typeof row.name === 'string' &&
          (!inbox || row.source === 'native_widget')
      );
      return { id, name: row.name };
    });
    check(new Set(list.map(row => row.id)).size === list.length);
    return list;
  };
  return {
    inboxes: rows('inboxes', true),
    execution_memberships: rows('execution_memberships'),
  };
}
