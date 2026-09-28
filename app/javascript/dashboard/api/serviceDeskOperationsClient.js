import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access.js';
import { normalizeQuery } from '../routes/dashboard/serviceDesk/helpers/query.js';
const RELATED = new Set(['notes', 'events', 'sla', 'conversations', 'status_options']);
const id = value => { const result = canonicalId(value); if (!result) throw new TypeError('Invalid identifier'); return result; };
const base = account => `/api/v1/accounts/${id(account)}/jrc_service_desk`;
const version = value => { if (!Number.isSafeInteger(value) || value < 0) throw new TypeError('Invalid version'); return value; };
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const fields = (value, allowed) => {
  if (!object(value) || Object.keys(value).some(key => !allowed.includes(key))) throw new TypeError('Unsupported fields');
  return { ...value };
};
const key = value => {
  if (typeof value !== 'string' || !/^[A-Za-z0-9._:-]{1,120}$/.test(value)) throw new TypeError('Invalid request key');
  return value;
};
// Explicit commands; there is no caller-supplied URL or arbitrary method.
export function createServiceDeskOperationsClient(http) {
  const get = (url, params, signal) => http.get(url, { params, signal, timeout: 20000 }).then(response => response.data);
  const post = (url, payload, signal, requestKey) => http.post(url, payload, {
    signal, timeout: 30000, ...(requestKey ? { headers: { 'Idempotency-Key': key(requestKey) } } : {}),
  }).then(response => response.data);
  return Object.freeze({
    dashboard: (account, query, signal) => get(`${base(account)}/dashboard`, normalizeQuery(query), signal),
    ticket: (account, ticketId, signal) => get(`${base(account)}/tickets/${id(ticketId)}`, {}, signal),
    relatedItem: (account, ticketId, kind, recordId, signal) => {
      if (!['notes', 'conversations'].includes(kind)) throw new TypeError('Invalid related item');
      return get(`${base(account)}/tickets/${id(ticketId)}/${kind}/${id(recordId)}`, {}, signal);
    },
    related: (account, ticketId, kind, query, signal) => {
      if (!RELATED.has(kind) || Object.keys(query || {}).some(k => !['page', 'per_page'].includes(k))) throw new TypeError('Invalid relation');
      return get(`${base(account)}/tickets/${id(ticketId)}/${kind}`, normalizeQuery(query), signal);
    },
    create: (account, payload, signal) => {
      fields(payload, ['unit_id', 'ticket', 'conversation_id', 'requestKey', 'service_id']);
      const ticket = fields(payload.ticket, ['title', 'description', 'requester_id', 'priority_id', 'category_id', 'status_id', 'queue_id', 'team_id', 'assignee_account_user_id']);
      return post(`${base(account)}/tickets`, { unit_id: id(payload.unit_id), ticket,
        ...(payload.service_id ? { service_id: id(payload.service_id) } : {}),
        ...(payload.conversation_id ? { conversation_id: id(payload.conversation_id) } : {}),
      }, signal, key(payload.requestKey));
    },
    update: (account, payload, signal) => {
      fields(payload, ['ticketId', 'ticket', 'expected_lock_version']);
      return http.patch(`${base(account)}/tickets/${id(payload.ticketId)}`, {
        ticket: fields(payload.ticket, ['title', 'description', 'priority_id', 'category_id']),
        expected_lock_version: version(payload.expected_lock_version),
      }, { signal, timeout: 30000 }).then(response => response.data);
    },
    assign: (account, payload, signal) => {
      fields(payload, ['ticketId', 'assignment', 'expected_lock_version']);
      return post(`${base(account)}/tickets/${id(payload.ticketId)}/assign`, {
        assignment: fields(payload.assignment, ['assignee_account_user_id', 'team_id', 'queue_id']),
        expected_lock_version: version(payload.expected_lock_version),
      }, signal);
    },
    transfer: (account, payload, signal) => {
      fields(payload, ['ticketId', 'assignment', 'expected_lock_version']);
      return post(`${base(account)}/tickets/${id(payload.ticketId)}/transfer`, {
        assignment: fields(payload.assignment, ['assignee_account_user_id', 'team_id', 'queue_id']),
        expected_lock_version: version(payload.expected_lock_version),
      }, signal);
    },
    work_status: (account, payload, signal) => {
      fields(payload, ['ticketId', 'status_id', 'expected_lock_version']);
      return post(`${base(account)}/tickets/${id(payload.ticketId)}/work_status`, {
        status_id: id(payload.status_id), expected_lock_version: version(payload.expected_lock_version),
      }, signal);
    },
    add_note: (account, payload, signal) => {
      fields(payload, ['ticketId', 'note', 'requestKey']);
      return post(`${base(account)}/tickets/${id(payload.ticketId)}/notes`, {
        note: fields(payload.note, ['body']),
      }, signal, key(payload.requestKey));
    },
    link_conversation: (account, payload, signal) => {
      fields(payload, ['ticketId', 'conversation_id']);
      return post(`${base(account)}/tickets/${id(payload.ticketId)}/conversations`, {
        conversation_id: id(payload.conversation_id),
      }, signal);
    },
  });
}
