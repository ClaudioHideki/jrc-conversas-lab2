import { canonicalId } from './access';
import { ContractError } from './contracts';
export const incidentStates = [
  'open',
  'investigating',
  'monitoring',
  'resolved',
];
const check = value => {
  if (!value) throw new ContractError();
};
export function decodeIncident(row, context, unitId, kind) {
  check(
    row &&
      row.account_id === context.account_id &&
      row.unit_id === unitId &&
      context.units.some(unit => unit.id === unitId) &&
      canonicalId(row.id) &&
      row.permissions?.show === true
  );
  check(row.resource_kind === kind && incidentStates.includes(row.status));
  check(
    typeof row.title === 'string' &&
      ['low', 'normal', 'high', 'critical'].includes(row.severity)
  );
  check(
    Number.isSafeInteger(row.lock_version) &&
      row.lock_version >= 0 &&
      Array.isArray(row.ticket_ids)
  );
  const ids = row.ticket_ids.map(value => {
    const id = canonicalId(value);
    check(id);
    return id;
  });
  check(new Set(ids).size === ids.length);
  return {
    id: row.id,
    account_id: row.account_id,
    unit_id: unitId,
    title: row.title,
    description: row.description,
    resource_kind: kind,
    status: row.status,
    severity: row.severity,
    lock_version: row.lock_version,
    owner_account_user_id: row.owner_account_user_id
      ? canonicalId(row.owner_account_user_id)
      : null,
    impact: row.impact || '',
    cause: row.cause || '',
    workaround: row.workaround || '',
    resolution: row.resolution || '',
    ticket_ids: ids,
    primary_ticket_id: row.primary_ticket_id,
    permissions: { show: true, update: row.permissions.update === true },
  };
}
