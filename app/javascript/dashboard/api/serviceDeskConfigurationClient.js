import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access.js';
import { CONFIGURATION_RESOURCES, configurationAttributes, configurationRevision } from '../routes/dashboard/serviceDesk/helpers/configuration.js';
const id = value => { const result = canonicalId(value); if (!result) throw new TypeError('Invalid identifier'); return result; };
const resourcePath = (account, resource) => {
  if (!CONFIGURATION_RESOURCES.includes(resource)) throw new TypeError('Unknown configuration resource');
  return `/api/v1/accounts/${id(account)}/jrc_service_desk/configuration/${resource}`;
};
const key = value => { if (typeof value !== 'string' || !/^[A-Za-z0-9._:-]{1,120}$/.test(value)) throw new TypeError('Invalid request key'); return value; };
export function createServiceDeskConfigurationClient(http) {
  const get = (url, params, signal) => http.get(url, { params, signal, timeout: 20000 }).then(r => r.data);
  return Object.freeze({
    portalOptions(account, unit, inbox, signal) {
      return get(
        `/api/v1/accounts/${id(account)}/jrc_service_desk/configuration/portal_options`,
        { unit_id: id(unit), ...(inbox ? { inbox_id: id(inbox) } : {}) },
        signal
      );
    },
    list(account, resource, unit, { page = 1, q = '', active = 'all' } = {}, signal) {
      if (!Number.isInteger(page) || page < 1 || page > 1000000 || typeof q !== 'string' || q.length > 200 || !['all', 'true', 'false'].includes(active)) throw new TypeError('Invalid query');
      return get(resourcePath(account, resource), { unit_id: id(unit), page, per_page: 20, q, active }, signal);
    },
    record: (account, resource, recordId, signal) => get(`${resourcePath(account, resource)}/${id(recordId)}`, {}, signal),
    receipt: (account, resource, recordId, auditId, signal) => get(`${resourcePath(account, resource)}/${id(recordId)}/receipts/${id(auditId)}`, {}, signal),
    save(account, intent, requestKey, signal) {
      const root = resourcePath(account, intent.resource);
      const create = intent.action === 'create';
      if (!create && intent.action !== 'update') throw new TypeError('Unknown action');
      const record = configurationAttributes(intent.resource, intent.attributes, create);
      const body = create ? { unit_id: id(intent.unitId), record } : { record, expected_revision: configurationRevision(intent.revision) };
      const config = { signal, timeout: 30000, headers: { 'Idempotency-Key': key(requestKey) } };
      return (create ? http.post(root, body, config) : http.patch(`${root}/${id(intent.recordId)}`, body, config)).then(r => r.data);
    },
  });
}
