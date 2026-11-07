const positive = value => Number.isSafeInteger(value) && value > 0;
const numeric = value => typeof value === 'number' && Number.isFinite(value);
const facts = [
  'current',
  'incoming',
  'projected',
  'effective_capacity',
  'available_after',
];
const blockers = [
  null,
  'capacity_missing',
  'capacity_workload_missing',
  'capacity_owner_unavailable',
  'capacity_exceeded',
];
export const validMembershipCapacity = (value, groupId) => {
  if (value === undefined) return true; // Existing immutable reviews predate this projection.
  if (
    !value ||
    value.read_only !== true ||
    typeof value.captured_at !== 'string' ||
    !Number.isFinite(Date.parse(value.captured_at)) ||
    ![
      'projected',
      'not_configured',
      'scope_denied',
      'controlled_review_required',
    ].includes(value.state) ||
    !Array.isArray(value.rows) ||
    value.rows.length > 50 ||
    Object.hasOwn(value, 'source_assignment_ids')
  )
    return false;
  if (value.state !== 'projected') return value.rows.length === 0;
  return value.rows.every(
    row =>
      positive(row?.user_id) &&
      positive(row.configuration_version) &&
      row.scope_key === `portfolio:${groupId}` &&
      ['customers', 'points', 'hours'].includes(row.unit) &&
      blockers.includes(row.blocker) &&
      (['capacity_missing', 'capacity_workload_missing'].includes(row.blocker)
        ? facts.every(key => !Object.hasOwn(row, key))
        : facts.every(key => numeric(row[key])) &&
          row.current >= 0 &&
          row.projected >= 0 &&
          row.effective_capacity >= 0)
  );
};
