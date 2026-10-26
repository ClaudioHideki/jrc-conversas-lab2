// Matches the native snapshot-calendar boundary contract, including 24:00 as
// an end-of-day boundary. No hours are guessed for a closed day.
export function calendarMinute(value) {
  if (
    typeof value !== 'string' ||
    !/^(?:[01]\d|2[0-3]):[0-5]\d$|^24:00$/.test(value)
  )
    return null;
  const [hours, minutes] = value.split(':').map(Number);
  return hours * 60 + minutes;
}

export function calendarIntervalsError(rows) {
  if (!Array.isArray(rows) || rows.length > 48) return 'interval_format';
  let previous = -1;
  return Array.from(rows).reduce((error, pair) => {
    if (error) return error;
    if (!Array.isArray(pair) || pair.length !== 2) return 'interval_format';
    const first = calendarMinute(pair[0]);
    const last = calendarMinute(pair[1]);
    if (first === null || last === null) return 'interval_time';
    if (first >= last) return 'interval_order';
    if (first < previous) return 'interval_overlap';
    previous = last;
    return null;
  }, null);
}

export function parseCalendarIntervals(input) {
  if (typeof input !== 'string')
    return { valid: false, rows: null, error: 'interval_format' };
  const rows = input.trim()
    ? input.split(/[;,]/).map(period => period.trim().split(/\s*-\s*/))
    : [];
  const error = calendarIntervalsError(rows);
  return { valid: error === null, rows: error ? null : rows, error };
}

// A malformed private draft must remain visible and repairable. Formatting
// never changes its stored rows or silently turns them into a valid policy.
export function formatCalendarIntervals(rows) {
  if (typeof rows === 'string') return rows;
  if (!Array.isArray(rows)) return JSON.stringify(rows ?? null);
  return rows
    .map(pair =>
      Array.isArray(pair)
        ? pair.map(value => String(value ?? '')).join('-')
        : String(pair ?? '')
    )
    .join(';');
}
