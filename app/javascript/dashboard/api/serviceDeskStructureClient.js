import { structureId, STRUCTURE_RESOURCES, structureAttributes } from '../routes/dashboard/serviceDesk/helpers/structure.js';
const base = account => `/api/v1/accounts/${structureId(account)}/jrc_service_desk/structure`;
const path = (account, resource) => {
  if (!STRUCTURE_RESOURCES.includes(resource)) throw new TypeError('Invalid structural resource');
  return `${base(account)}/${resource}`;
};
export function createServiceDeskStructureClient(http) {
  const get = (url, params, signal) => http.get(url, { params, signal, timeout: 20000 }).then(response => response.data);
  return Object.freeze({
    context: (account, signal) => get(`${base(account)}/context`, {}, signal),
    list(account, resource, page = 1, q = '', signal) {
      if (!Number.isInteger(page) || page < 1 || page > 1000000 || typeof q !== 'string' || q.length > 200) throw new TypeError('Invalid query');
      return get(resource === 'members' ? `${base(account)}/members` : path(account, resource), { page, q }, signal);
    },
    record: (account, resource, id, signal) => get(`${path(account, resource)}/${structureId(id)}`, {}, signal),
    receipt: (account, resource, id, auditId, signal) => get(`${path(account, resource)}/${structureId(id)}/receipts/${structureId(auditId)}`, {}, signal),
    save(account, intent, key, signal) {
      if (!['create', 'update'].includes(intent.action) || typeof key !== 'string' || !/^[a-zA-Z0-9._:-]{1,120}$/.test(key)) throw new TypeError('Invalid request');
      if (typeof intent.reason !== 'string' || intent.reason.trim().length < 3 || intent.reason.trim().length > 500) throw new TypeError('Authorization reference required');
      const record = structureAttributes(intent.resource, intent.attributes, intent.action === 'create');
      const payload = { record, reason: intent.reason.trim() };
      const config = { signal, timeout: 30000, headers: { 'Idempotency-Key': key } };
      if (intent.action === 'create') return http.post(path(account, intent.resource), payload, config).then(r => r.data);
      if (typeof intent.revision !== 'string' || !/^[a-f0-9]{64}$/.test(intent.revision)) throw new TypeError('Revision required');
      payload.expected_revision = intent.revision;
      return http.patch(`${path(account, intent.resource)}/${structureId(intent.recordId)}`, payload, config).then(r => r.data);
    },
  });
}
