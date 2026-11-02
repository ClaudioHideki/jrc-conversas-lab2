import { blankLifecycleDraft } from '../helpers/lifecycleDesigner';
import { validCalendar, validCalendarHours } from './calendarRules';
export const clone = value => JSON.parse(JSON.stringify(value));
export const emptyCalendar = () => ({
  timezone: '',
  conditions: {
    format: 'jrc-sd-snapshot-calendar-v1',
    weekly: Object.fromEntries(
      [1, 2, 3, 4, 5, 6, 7].map(day => [String(day), []])
    ),
    holidays: [],
    exceptions: {},
  },
});
export const emptyConditions = () => ({
  operator: 'all',
  groups: [{ operator: 'all', items: [] }],
});
export const emptyRule = () => ({
  key: crypto.randomUUID(),
  precedence: null,
  match: {},
  conditions: emptyConditions(),
  output: { queue_id: null },
});
export function blankComposition(kind) {
  return {
    kind,
    code: '',
    name: '',
    description: '',
    service_id: null,
    enabled: false,
    definition: {
      lifecycle:
        kind === 'lifecycle' ? JSON.parse(blankLifecycleDraft()) : null,
      families:
        kind === 'operational' ? { routing: { rules: [emptyRule()] } } : {},
      queues: [],
      notifications: [],
    },
  };
}
export function stable(value) {
  if (Array.isArray(value)) return `[${value.map(stable).join(',')}]`;
  if (value && typeof value === 'object')
    return `{${Object.keys(value)
      .sort()
      .map(key => `${JSON.stringify(key)}:${stable(value[key])}`)
      .join(',')}}`;
  return JSON.stringify(value);
}
export function snapshotFor(
  attributes,
  version,
  calendar,
  calendarCode,
  calendarVersion,
  budgets = {}
) {
  return {
    source_system: 'jrc_service_desk',
    source_reference: attributes.code,
    source_version: String(version + 1),
    policy_key: attributes.code,
    policy_version: String(version + 1),
    calendar_key: calendarCode,
    calendar_version: String(calendarVersion || ''),
    calendar_scope: 'unit',
    timezone: calendar.timezone,
    calendar_conditions: clone(calendar.conditions),
    contract_conditions: {},
    policy_conditions: { clock_budgets_seconds: clone(budgets) },
  };
}
export function compositionPayload(
  attributes,
  version,
  calendar,
  calendarCode,
  calendarVersion
) {
  const result = clone(attributes);
  const families = result.definition.families;
  Object.values(families).forEach(family =>
    family.rules.forEach(row => {
      if (result.service_id) row.match.service_id = Number(result.service_id);
      if (row.valid_from === '') delete row.valid_from;
      if (row.valid_until === '') delete row.valid_until;
      if (
        row.conditions?.groups.length === 1 &&
        !row.conditions.groups[0].items.length &&
        Object.keys(row.match).length
      )
        delete row.conditions;
    })
  );
  families.sla_selection?.rules.forEach(row => {
    row.output.snapshot = snapshotFor(
      result,
      version,
      calendar,
      calendarCode,
      calendarVersion,
      row.output.snapshot.policy_conditions.clock_budgets_seconds
    );
  });
  return result;
}
export function compositionCalendars(attributes, calendar) {
  const definition = attributes.definition;
  return [
    ...(definition.lifecycle?.sla.mode === 'calendar_snapshot' ||
    definition.families.sla_selection?.rules.length
      ? [calendar]
      : []),
    ...definition.queues
      .filter(row => row.attributes.ola_time_basis === 'business')
      .map(row => row.attributes.ola_calendar),
    ...Object.values(definition.families).flatMap(family =>
      family.rules.filter(row => row.window != null).map(row => row.window)
    ),
    ...definition.notifications
      .filter(row => row.settings?.window?.enabled)
      .map(row => row.settings.window),
  ];
}
export function validCompositionCalendars(attributes, calendar) {
  return compositionCalendars(attributes, calendar).every(validCalendar);
}
export function validCompositionCalendarHours(attributes, calendar) {
  return compositionCalendars(attributes, calendar).every(validCalendarHours);
}
export function publicationMatches(row, payload, expectedVersion) {
  return (
    row &&
    row.version === expectedVersion + 1 &&
    /^[a-f0-9]{64}$/.test(row.digest) &&
    [
      'kind',
      'code',
      'name',
      'description',
      'service_id',
      'enabled',
      'definition',
    ].every(key => stable(row[key]) === stable(payload[key]))
  );
}
export const predicateResources = Object.freeze({
  category_id: 'categories',
  service_id: 'services',
  priority_id: 'priorities',
  ticket_type_id: 'ticket_types',
  inbox_id: 'inboxes',
  company_id: 'companies',
  contract_id: 'contracts',
});
export const predicateFields = Object.freeze([
  ...Object.keys(predicateResources),
  'channel_type',
  'impact',
  'urgency',
  'label_id',
  'form_value',
]);
