import { calendarIntervalsError } from './calendarIntervals';

// Drafts may be incomplete, but a typed malformed period cannot be silently
// saved or sent as a publishable calendar. Full publication checks stay below.
export function validCalendarHours(value) {
  const data = value?.conditions;
  if (data == null) return true;
  if (typeof data !== 'object' || Array.isArray(data)) return false;
  return ['weekly', 'exceptions'].every(key => {
    const entries = data[key];
    return (
      entries == null ||
      (typeof entries === 'object' &&
        !Array.isArray(entries) &&
        Object.values(entries).every(
          rows => calendarIntervalsError(rows) === null
        ))
    );
  });
}

export function validCalendar(value) {
  try {
    if (!value || typeof value.timezone !== 'string' || !value.timezone.trim())
      return false;
    new Intl.DateTimeFormat('en-US', { timeZone: value.timezone }).format();
    const data = value.conditions;
    if (
      data?.format !== 'jrc-sd-snapshot-calendar-v1' ||
      !data.weekly ||
      Array.isArray(data.weekly)
    )
      return false;
    const days = ['1', '2', '3', '4', '5', '6', '7'];
    if (
      JSON.stringify(Object.keys(data.weekly).sort()) !== JSON.stringify(days)
    )
      return false;
    const date = input =>
      typeof input === 'string' &&
      /^\d{4}-\d{2}-\d{2}$/.test(input) &&
      new Date(`${input}T00:00:00Z`).toISOString().slice(0, 10) === input;
    if (
      !Array.isArray(data.holidays) ||
      data.holidays.length > 10000 ||
      !data.holidays.every(date)
    )
      return false;
    if (
      !data.exceptions ||
      Array.isArray(data.exceptions) ||
      typeof data.exceptions !== 'object' ||
      Object.keys(data.exceptions).length > 10000
    )
      return false;
    if (
      !Object.entries(data.exceptions).every(
        ([key, rows]) => date(key) && calendarIntervalsError(rows) === null
      )
    )
      return false;
    return (
      Object.values(data.weekly).every(
        rows => calendarIntervalsError(rows) === null
      ) &&
      [...Object.values(data.weekly), ...Object.values(data.exceptions)].some(
        rows => rows.length > 0
      )
    );
  } catch {
    return false;
  }
}
