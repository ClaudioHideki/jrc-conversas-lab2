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
    const minute = input => {
      if (
        typeof input !== 'string' ||
        !/^(?:[01]\d|2[0-3]):[0-5]\d$|^24:00$/.test(input)
      )
        return null;
      const [hours, minutes] = input.split(':').map(Number);
      return hours * 60 + minutes;
    };
    const intervals = rows => {
      if (!Array.isArray(rows) || rows.length > 48) return false;
      let previous = -1;
      return rows.every(pair => {
        if (!Array.isArray(pair) || pair.length !== 2) return false;
        const first = minute(pair[0]);
        const last = minute(pair[1]);
        if (first == null || last == null || first >= last || first < previous)
          return false;
        previous = last;
        return true;
      });
    };
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
        ([key, rows]) => date(key) && intervals(rows)
      )
    )
      return false;
    return (
      Object.values(data.weekly).every(intervals) &&
      [...Object.values(data.weekly), ...Object.values(data.exceptions)].some(
        rows => rows.length > 0
      )
    );
  } catch {
    return false;
  }
}
