// Values must come from already-authorized projections. Never impute missing data.
export function finiteDuration(value) {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0
    ? Math.round(value)
    : null;
}
export function capacityPresentation(row) {
  const measured =
    Number.isSafeInteger(row?.capacity) &&
    row.capacity > 0 &&
    Number.isSafeInteger(row?.active_tickets) &&
    row.active_tickets >= 0;
  return measured
    ? {
        percent: Math.round((100 * row.active_tickets) / row.capacity),
        progress: Math.min(row.active_tickets, row.capacity),
        maximum: row.capacity,
      }
    : null;
}
export function recentTicketActivity(rows) {
  return rows
    .filter(row => row?.id && Number.isFinite(Date.parse(row.updated_at)))
    .slice()
    .sort((a, b) => Date.parse(b.updated_at) - Date.parse(a.updated_at))
    .slice(0, 5);
}
