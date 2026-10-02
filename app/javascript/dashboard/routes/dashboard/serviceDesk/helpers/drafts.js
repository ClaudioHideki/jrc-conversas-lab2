import { canonicalId } from './access.js';
const id = value => { const result = canonicalId(value); if (!result) throw new TypeError('Invalid identifier'); return result; };
const text = value => { if (typeof value !== 'string') throw new TypeError('Invalid text'); return value; };
export function createTicketDraft(
  draft,
  unit,
  requestKey,
  customerMaster = false
) {
  if (!unit || unit.id !== id(draft.unit_id) || unit.permissions.create_ticket !== true) throw new TypeError('Unit not authorized');
  const ticket = { title: text(draft.title), description: text(draft.description),
    requester_id: id(draft.requester_id), priority_id: id(draft.priority_id), status_id: id(unit.initial_status?.id) };
  if (!ticket.title.trim() || ticket.title.length > 255) throw new TypeError('Invalid title');
  ['category_id', 'queue_id', 'team_id'].forEach(key => { if (draft[key]) ticket[key] = id(draft[key]); });
  if (customerMaster && draft.company_id) ticket.company_id = id(draft.company_id);
  if (draft.assignee_id) ticket.assignee_account_user_id = id(draft.assignee_id);
  return { unit_id: unit.id, ticket, requestKey, ...(draft.service_id ? { service_id: id(draft.service_id) } : {}), ...(draft.conversation_id ? { conversation_id: id(draft.conversation_id) } : {}) };
}
export function updateTicketDraft(draft, record, customerMaster = false) {
  if (!record?.permissions?.update || record.unit_id !== id(draft.unit_id)) throw new TypeError('Record not editable');
  return { ticketId: record.id, expected_lock_version: record.lock_version,
    ticket: {
      title: text(draft.title),
      description: text(draft.description),
      ...(customerMaster &&
      String(draft.company_id || '') !== String(record.company?.id || '')
        ? { company_id: draft.company_id ? id(draft.company_id) : null }
        : {}),
      ...(record.permissions.change_priority === true
        ? { priority_id: id(draft.priority_id) }
        : {}),
      category_id: draft.category_id ? id(draft.category_id) : null,
    },
  };
}
export function newRequestKey() {
  if (typeof globalThis.crypto?.randomUUID === 'function') return globalThis.crypto.randomUUID();
  if (typeof globalThis.crypto?.getRandomValues !== 'function')
    throw new TypeError('Secure request key unavailable');
  const bytes = globalThis.crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, value => value.toString(16).padStart(2, '0')).join('');
}
