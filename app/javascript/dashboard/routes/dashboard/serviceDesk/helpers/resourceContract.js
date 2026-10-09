import { canonicalId } from './access';
import { ContractError } from './contracts';

export const resourceStates = Object.freeze({
  change: [
    'requested',
    'planned',
    'approved',
    'in_progress',
    'completed',
    'cancelled',
  ],
  asset: ['active', 'inactive', 'retired'],
});
export const resourceTransitions = Object.freeze({
  requested: ['planned', 'cancelled'],
  planned: ['approved', 'cancelled'],
  approved: ['in_progress', 'cancelled'],
  in_progress: ['completed', 'cancelled'],
  active: ['inactive', 'retired'],
  inactive: ['active', 'retired'],
});

export function decodeResource(row, context, unitId, kind) {
  const valid =
    row &&
    canonicalId(row.id) &&
    row.account_id === context.account_id &&
    row.unit_id === unitId &&
    context.units.some(unit => unit.id === unitId) &&
    row.resource_kind === kind &&
    resourceStates[kind]?.includes(row.state) &&
    row.permissions?.show === true &&
    typeof row.name === 'string' &&
    ['low', 'normal', 'high', 'critical'].includes(row.priority) &&
    Number.isSafeInteger(row.lock_version) &&
    row.lock_version >= 0 &&
    Array.isArray(row.history) &&
    Array.isArray(row.ticket_ids) &&
    row.ticket_ids.every(value => canonicalId(value)) &&
    new Set(row.ticket_ids).size === row.ticket_ids.length &&
    row.details &&
    typeof row.details === 'object' &&
    !Array.isArray(row.details);
  if (!valid) throw new ContractError();
  return {
    id: row.id,
    account_id: row.account_id,
    unit_id: row.unit_id,
    resource_kind: row.resource_kind,
    name: row.name,
    code: row.code || '',
    description: row.description || '',
    state: row.state,
    priority: row.priority,
    owner_account_user_id: row.owner_account_user_id || null,
    company_id: row.company_id || null,
    approval_id: row.approval_id || null,
    planned_start_at: row.planned_start_at,
    planned_end_at: row.planned_end_at,
    details: row.details,
    history: row.history,
    ticket_ids: row.ticket_ids,
    lock_version: row.lock_version,
    permissions: {
      show: true,
      update: row.permissions.update === true,
      destroy: row.permissions.destroy === true,
    },
  };
}

export function decodeResources(payload, context, unitId, kind, page) {
  if (
    payload?.contract_version !== 1 ||
    payload.account_id !== context.account_id ||
    !Array.isArray(payload.items) ||
    payload.meta?.page !== page ||
    payload.meta.per_page !== 20 ||
    !Number.isSafeInteger(payload.meta.total) ||
    payload.meta.total < payload.items.length ||
    payload.items.length > 20 ||
    payload.items.length > Math.max(0, payload.meta.total - (page - 1) * 20)
  )
    throw new ContractError();
  const items = payload.items.map(row =>
    decodeResource(row, context, unitId, kind)
  );
  if (new Set(items.map(row => row.id)).size !== items.length)
    throw new ContractError();
  return { items, meta: payload.meta };
}
