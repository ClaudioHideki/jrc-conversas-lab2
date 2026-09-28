import { canonicalId } from './access.js';

export const CONFIGURATION_RESOURCES = Object.freeze(['queues', 'categories', 'priorities', 'statuses', 'services']);
export const CONFIGURATION_PHASES = Object.freeze(['open', 'waiting', 'resolved', 'closed', 'cancelled']);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const check = value => { if (!value) throw new TypeError('Invalid configuration contract'); };
const id = value => { const result = canonicalId(value); check(result !== null); return result; };
export const configurationFields = resource => {
  check(CONFIGURATION_RESOURCES.includes(resource));
  return ['name', 'code', 'active', ...(resource === 'queues' ? ['team_id'] : []),
    ...(['priorities', 'statuses'].includes(resource) ? ['position'] : []), ...(resource === 'statuses' ? ['phase', 'initial'] : [])];
};
export function configurationAttributes(resource, data, create = true) {
  const allowed = configurationFields(resource).filter(field => create || field !== 'code');
  check(object(data) && Object.keys(data).length && Object.keys(data).every(field => allowed.includes(field)));
  if (create) check(allowed.filter(field => field !== 'team_id').every(field => Object.hasOwn(data, field)));
  const result = { ...data };
  for (const [field, value] of Object.entries(result)) {
    if (['name', 'code'].includes(field)) check(typeof value === 'string' && value.trim().length > 0 && value.length <= (field === 'code' ? 80 : 255));
    if (['active', 'initial'].includes(field)) check(typeof value === 'boolean');
    if (field === 'position') check(Number.isInteger(value) && value >= 0 && value <= 2147483647);
    if (field === 'phase') check(CONFIGURATION_PHASES.includes(value));
    if (field === 'team_id') result[field] = value === null ? null : id(value);
  }
  return result;
}
export function configurationRevision(value) {
  check(typeof value === 'string' && /^[a-f0-9]{64}$/.test(value)); return value;
}
export function decodeConfigurationRecord(row, context, resource, unitId) {
  check(object(row) && id(row.account_id) === context.account_id && id(row.unit_id) === id(unitId));
  check(context.units.some(unit => unit.id === id(unitId)) && context.capabilities?.configuration?.[resource] === true);
  const fields = Object.fromEntries(configurationFields(resource).filter(field => Object.hasOwn(row, field)).map(field => [field, row[field]]));
  return { ...configurationAttributes(resource, fields), id: id(row.id), account_id: context.account_id, unit_id: id(unitId),
    revision: configurationRevision(row.revision), created_at: row.created_at, updated_at: row.updated_at };
}
export function decodeConfigurationPage(payload, context, resource, unitId, page) {
  check(object(payload) && payload.contract_version === 1 && id(payload.account_id) === context.account_id && payload.resource === resource);
  check(id(payload.unit_id) === id(unitId) && Array.isArray(payload.items));
  const meta = payload.meta;
  check(object(meta) && Number.isSafeInteger(meta.total) && meta.total >= 0 && meta.page === page && meta.per_page === 20);
  const remaining = Math.max(0, meta.total - (page - 1) * 20);
  check(payload.items.length === Math.min(20, remaining));
  const items = payload.items.map(row => decodeConfigurationRecord(row, context, resource, unitId));
  check(new Set(items.map(row => row.id)).size === items.length);
  return { items, meta };
}
export function decodeConfigurationEnvelope(payload, context, resource, unitId) {
  check(object(payload) && payload.contract_version === 1 && id(payload.account_id) === context.account_id && payload.resource === resource);
  return decodeConfigurationRecord(payload.record, context, resource, unitId);
}
export function confirmConfiguration(receiptPayload, recordPayload, intent, context) {
  const { resource, unitId, attributes, action } = intent;
  check(object(receiptPayload) && receiptPayload.contract_version === 1 && id(receiptPayload.account_id) === context.account_id);
  const receipt = receiptPayload.receipt;
  check(object(receipt) && receipt.resource === resource && id(receipt.account_id) === context.account_id && id(receipt.unit_id) === unitId && receipt.action === action);
  check(typeof receipt.occurred_at === 'string' && Number.isFinite(Date.parse(receipt.occurred_at)));
  const record = decodeConfigurationEnvelope(recordPayload, context, resource, unitId);
  check(record.id === id(receipt.record_id) && (!intent.recordId || record.id === intent.recordId));
  check(id(receipt.id) === id(intent.auditId));
  const after = configurationAttributes(resource, receipt.after);
  const desired = configurationAttributes(resource, attributes, action === 'create');
  for (const [field, value] of Object.entries(desired)) check(record[field] === value && after[field] === value);
  return record;
}
