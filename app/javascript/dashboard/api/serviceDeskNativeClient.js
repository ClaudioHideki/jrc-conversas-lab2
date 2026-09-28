import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access.js';
const id = value => { const result = canonicalId(value); if (!result) throw new TypeError('Invalid identifier'); return result; };
export function createServiceDeskNativeClient(http) {
  const base = (account, ticket) => `/api/v1/accounts/${id(account)}/jrc_service_desk/tickets/${id(ticket)}`;
  const get = (url, signal) => http.get(url, { signal, timeout: 15000 }).then(response => response.data);
  return Object.freeze({
    customer: (account, ticket, signal) => get(`${base(account, ticket)}/customer_context`, signal),
    conversation: (account, ticket, link, signal) => get(`${base(account, ticket)}/conversations/${id(link)}/navigation`, signal),
  });
}
