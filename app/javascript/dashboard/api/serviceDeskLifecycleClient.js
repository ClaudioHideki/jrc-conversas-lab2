import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access.js';
const id = value => { const result = canonicalId(value); if (!result) throw new TypeError('Invalid lifecycle identifier'); return result; };
const root = account => `/api/v1/accounts/${id(account)}/jrc_service_desk`;
const fields = (value, allowed) => {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(key => !allowed.includes(key))) throw new TypeError('Invalid lifecycle fields');
  return { ...value };
};
const version = value => { if (!Number.isSafeInteger(value) || value < 0) throw new TypeError('Invalid lock version'); return value; };
export function createServiceDeskLifecycleClient(http) {
  const get = (url, params, signal) => http.get(url, { params, signal, timeout: 20000 }).then(r => r.data);
  const post = (url, body, signal, requestKey) => {
    if (requestKey !== undefined && (typeof requestKey !== 'string' || !/^[A-Za-z0-9._:-]{1,120}$/.test(requestKey))) throw new TypeError('Invalid lifecycle request key');
    return http.post(url, body, { signal, timeout: 30000, ...(requestKey ? { headers: { 'Idempotency-Key': requestKey } } : {}) }).then(r => r.data);
  };
  return Object.freeze({
    read: (account, ticket, page, signal) => get(`${root(account)}/tickets/${id(ticket)}/lifecycle`, { page: id(page) }, signal),
    transition: (account, ticket, transition, signal) => get(`${root(account)}/tickets/${id(ticket)}/lifecycle/transitions/${id(transition)}`, {}, signal),
    ticket: (account, ticket, signal) => get(`${root(account)}/tickets/${id(ticket)}`, {}, signal),
    apply: (account, ticket, data, requestKey, signal) => {
      const body = fields(data, ['rule_key', 'expected_lock_version', 'expected_policy_version_id', 'reason_code', 'note', 'solution', 'evidence_note_ids', 'fields']);
      body.expected_lock_version = version(body.expected_lock_version);
      body.expected_policy_version_id = id(body.expected_policy_version_id);
      if (typeof body.rule_key !== 'string' || !/^[A-Za-z0-9_.-]{1,80}$/.test(body.rule_key)) throw new TypeError('Invalid rule');
      return post(`${root(account)}/tickets/${id(ticket)}/lifecycle`, body, signal, requestKey);
    },
    policies: (account, unit, page, signal) => get(`${root(account)}/lifecycle_policies`, { unit_id: id(unit), page: id(page) }, signal),
    policy: (account, policy, signal) => get(`${root(account)}/lifecycle_policies/${id(policy)}`, {}, signal),
    publish: (account, unit, policy, signal) => post(`${root(account)}/lifecycle_policies`, { unit_id: id(unit), policy: fields(policy, ['name', 'service_id', 'enabled', 'expected_version', 'definition']) }, signal),
    services: (account, unit, page, signal) => get(`${root(account)}/service_definitions`, { unit_id: id(unit), page: id(page) }, signal),
    service: (account, record, signal) => get(`${root(account)}/service_definitions/${id(record)}`, {}, signal),
    createService: (account, unit, service, signal) => post(`${root(account)}/service_definitions`, { unit_id: id(unit), service: fields(service, ['name', 'code', 'active']) }, signal),
  });
}
