import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access.js';
import { normalizeQuery } from '../routes/dashboard/serviceDesk/helpers/query.js';
const RESOURCES = new Set(['tickets', 'queues', 'priorities', 'categories', 'statuses', 'units', 'operator_companies', 'assignees', 'requesters', 'teams']);
const baseUrl = accountId => {
  const id = canonicalId(accountId);
  if (!id)
    throw new TypeError('Invalid account');
  return `/api/v1/accounts/${id}/jrc_service_desk`;
};
// Read-only structural adapter. Endpoints are proposed CP4 contracts, NOT
// implemented by CP3. Never falls back to another module, mock or local storage.
export function createServiceDeskClient(http) {
  const get = (url, params, signal) => http.get(url, { params, signal, timeout: 15000 }).then(response => response.data);
  return Object.freeze({
    context: (accountId, signal) => get(`${baseUrl(accountId)}/ui_context`, {}, signal),
    list: (accountId, resource, query, signal) => {
      if (!RESOURCES.has(resource))
        throw new TypeError('Unknown resource');
      const normalized = normalizeQuery(query);
      if (resource !== 'tickets' && Object.keys(normalized).some(key => !['q', 'page', 'per_page', 'unit_id', 'operator_company_id', 'sort'].includes(key))) {
        throw new TypeError('Unsupported resource filter');
      }
      if (['assignees', 'requesters', 'teams'].includes(resource) && !normalized.unit_id)
        throw new TypeError('Unit selection required');
      return get(`${baseUrl(accountId)}/${resource}`, normalized, signal);
    },
    ticket: (accountId, ticketId, signal) => {
      const id = canonicalId(ticketId);
      if (!id)
        throw new TypeError('Invalid ticket');
      return get(`${baseUrl(accountId)}/tickets/${id}`, {}, signal);
    },
  });
}
