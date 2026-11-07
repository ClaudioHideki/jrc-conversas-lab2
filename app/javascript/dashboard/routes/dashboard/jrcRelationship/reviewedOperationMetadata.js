const states = ['previewed', 'running', 'completed', 'canceled', 'attention'];
const counts = ['pending', 'applied', 'failed', 'canceled'];
export const validOperationMetadata = row =>
  Number.isSafeInteger(row?.id) &&
  row.id > 0 &&
  Number.isSafeInteger(row.revision) &&
  row.revision > 0 &&
  states.includes(row.state) &&
  [
    'assign',
    'playbook',
    'activity',
    'cadence',
    'portfolio_membership',
    'master_allocation',
  ].includes(row.operation) &&
  typeof row.can_cancel_pending === 'boolean' &&
  row.can_cancel_pending === ['previewed', 'running'].includes(row.state) &&
  counts.every(
    key => Number.isSafeInteger(row.counts?.[key]) && row.counts[key] >= 0
  ) &&
  Number.isSafeInteger(row.counts.total) &&
  row.counts.total >= 1 &&
  row.counts.total <= 50 &&
  counts.reduce((sum, key) => sum + row.counts[key], 0) === row.counts.total &&
  [row.created_at, row.updated_at].every(
    value => typeof value === 'string' && Number.isFinite(Date.parse(value))
  );
