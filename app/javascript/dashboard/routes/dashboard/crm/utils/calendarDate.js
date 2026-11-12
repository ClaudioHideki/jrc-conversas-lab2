// A YYYY-MM-DD navigation value is a calendar day, not a midnight UTC instant.
export const parseCalendarDate = value => {
  if (typeof value !== 'string' || !value.trim()) return null;
  const parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (parts) {
    const [, year, month, day] = parts.map(Number);
    const result = new Date(0);
    result.setFullYear(year, month - 1, day);
    result.setHours(0, 0, 0, 0);
    if (
      result.getFullYear() !== year ||
      result.getMonth() !== month - 1 ||
      result.getDate() !== day
    )
      return null;
    return result;
  }
  const result = new Date(value);
  return Number.isNaN(result.getTime()) ? null : result;
};
