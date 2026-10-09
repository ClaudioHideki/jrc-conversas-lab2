import { canonicalId } from './access';
import { ContractError } from './contracts';

export function decodeClockProjection(row) {
  const valid =
    row &&
    canonicalId(row.id) &&
    ['first_response', 'attendance', 'resolution', 'ola'].includes(row.kind) &&
    ['running', 'paused', 'completed', 'stopped'].includes(row.state) &&
    Number.isSafeInteger(row.budget_seconds) &&
    row.budget_seconds > 0 &&
    ['elapsed_seconds', 'remaining_seconds', 'consumed_percent'].every(
      key => Number.isFinite(row[key]) && row[key] >= 0
    ) &&
    typeof row.breached === 'boolean' &&
    Number.isFinite(Date.parse(row.due_at)) &&
    Number.isFinite(Date.parse(row.observed_at));
  if (!valid) throw new ContractError();
  return {
    id: canonicalId(row.id),
    kind: row.kind,
    state: row.state,
    budget_seconds: row.budget_seconds,
    elapsed_seconds: row.elapsed_seconds,
    remaining_seconds: row.remaining_seconds,
    consumed_percent: row.consumed_percent,
    breached: row.breached,
    due_at: row.due_at,
    observed_at: row.observed_at,
    timezone: typeof row.timezone === 'string' ? row.timezone : null,
    time_basis: row.time_basis === 'calendar' ? 'calendar' : 'business',
  };
}
