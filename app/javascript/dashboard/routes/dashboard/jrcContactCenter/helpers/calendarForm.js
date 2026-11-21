import { validCalendar } from 'dashboard/routes/dashboard/serviceDesk/automationStudio/calendarRules';

const fields = [
  'name',
  'description',
  'timezone',
  'weekly',
  'holidays',
  'exceptions',
];
const holidayFields = ['date', 'name', 'kind', 'type'];
const exceptionFields = ['date', 'name', 'intervals'];
const objectWithFields = (value, keys) =>
  value &&
  !Array.isArray(value) &&
  typeof value === 'object' &&
  JSON.stringify(Object.keys(value).sort()) ===
    JSON.stringify([...keys].sort());
const named = value =>
  typeof value === 'string' && value.trim().length > 0 && value.length <= 120;
const uniqueDates = rows =>
  new Set(rows.map(row => row.date)).size === rows.length;
// These are JSON request values, including typed invalid text. Vue proxies cannot be structuredClone'd.
const copy = value =>
  value === undefined ? undefined : JSON.parse(JSON.stringify(value));

// Only the native calendar wire contract; it does not inherit Service Desk access or change routing.
export const calendarSchedule = definition => ({
  timezone: definition.timezone,
  conditions: {
    format: 'jrc-sd-snapshot-calendar-v1',
    weekly: copy(definition.weekly),
    holidays: definition.holidays.map(row => row.date),
    exceptions: Object.fromEntries(
      definition.exceptions.map(row => [row.date, copy(row.intervals)])
    ),
  },
});

export const validCalendarDefinition = value => {
  if (
    !objectWithFields(value, fields) ||
    !named(value.name) ||
    typeof value.description !== 'string' ||
    value.description.length > 1000
  )
    return false;
  if (
    !Array.isArray(value.holidays) ||
    !Array.isArray(value.exceptions) ||
    value.holidays.length > 1000 ||
    value.exceptions.length > 1000
  )
    return false;
  if (
    !value.holidays.every(
      row =>
        objectWithFields(row, holidayFields) &&
        named(row.name) &&
        ['national', 'state', 'municipal', 'internal'].includes(row.kind) &&
        ['fixed', 'movable'].includes(row.type)
    )
  )
    return false;
  if (
    !value.exceptions.every(
      row => objectWithFields(row, exceptionFields) && named(row.name)
    )
  )
    return false;
  if (
    !uniqueDates(value.holidays) ||
    !uniqueDates(value.exceptions) ||
    new Blob([JSON.stringify(value)]).size > 65536
  )
    return false;
  return validCalendar(calendarSchedule(value));
};

// Preserve typed invalid interval text and require explicit metadata for newly selected dates.
export const updateCalendarSchedule = (definition, schedule) => ({
  ...definition,
  timezone: schedule.timezone,
  weekly: copy(schedule.conditions.weekly),
  holidays: schedule.conditions.holidays.map(date => ({
    ...(definition.holidays.find(row => row.date === date) || {
      name: '',
      kind: '',
      type: '',
    }),
    date,
  })),
  exceptions: Object.entries(schedule.conditions.exceptions).map(
    ([date, intervals]) => ({
      ...(definition.exceptions.find(row => row.date === date) || { name: '' }),
      date,
      intervals: copy(intervals),
    })
  ),
});

export const newCalendarDefinition = timezone => ({
  name: '',
  description: '',
  timezone,
  weekly: Object.fromEntries(
    [1, 2, 3, 4, 5, 6, 7].map(day => [String(day), []])
  ),
  holidays: [],
  exceptions: [],
});

export const normalizedCalendarDefinition = value => {
  const result = copy(value);
  result.name = result.name.trim();
  result.description = result.description.trim();
  result.holidays = result.holidays.map(row => ({
    ...row,
    name: row.name.trim(),
  }));
  result.exceptions = result.exceptions.map(row => ({
    ...row,
    name: row.name.trim(),
  }));
  return result;
};

// JSONB object key order is not content. Arrays retain their explicit user-reviewed order.
export const calendarDefinitionSignature = value =>
  JSON.stringify([
    value.name,
    value.description,
    value.timezone,
    ['1', '2', '3', '4', '5', '6', '7'].map(day => value.weekly[day]),
    value.holidays.map(row => [row.date, row.name, row.kind, row.type]),
    value.exceptions.map(row => [row.date, row.name, row.intervals]),
  ]);
