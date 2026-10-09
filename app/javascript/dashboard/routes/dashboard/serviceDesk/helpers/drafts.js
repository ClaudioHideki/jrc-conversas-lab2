/* global globalThis */
import { canonicalId } from './access.js';
const id = value => {
  const result = canonicalId(value);
  if (!result) throw new TypeError('Invalid identifier');
  return result;
};
const text = value => {
  if (typeof value !== 'string') throw new TypeError('Invalid text');
  return value;
};
export function createTicketDraft(
  draft,
  unit,
  requestKey,
  customerMaster = false
) {
  if (
    !unit ||
    unit.id !== id(draft.unit_id) ||
    unit.permissions.create_ticket !== true
  )
    throw new TypeError('Unit not authorized');
  const matrix = !!(draft.impact_code || draft.urgency_code);
  if (
    matrix &&
    ![draft.impact_code, draft.urgency_code].every(
      value =>
        typeof value === 'string' &&
        /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$/.test(value)
    )
  )
    throw new TypeError('Explicit impact and urgency required');
  const ticket = {
    title: text(draft.title),
    description: text(draft.description),
    requester_id: id(draft.requester_id),
    ...(matrix
      ? { impact_code: draft.impact_code, urgency_code: draft.urgency_code }
      : { priority_id: id(draft.priority_id) }),
    status_id: id(unit.initial_status?.id),
  };
  if (!ticket.title.trim() || ticket.title.length > 255)
    throw new TypeError('Invalid title');
  [
    'category_id',
    'ticket_type_id',
    'subcategory_id',
    'contract_id',
    'queue_id',
    'team_id',
  ].forEach(key => {
    if (
      draft[key] &&
      !(
        draft.use_channel_routing === true &&
        ['queue_id', 'team_id'].includes(key)
      )
    )
      ticket[key] = id(draft[key]);
  });
  if (customerMaster && draft.company_id)
    ticket.company_id = id(draft.company_id);
  if (draft.assignee_id && draft.use_channel_routing !== true)
    ticket.assignee_account_user_id = id(draft.assignee_id);
  if (
    draft.service_fields &&
    (draft.service_id || Object.keys(draft.service_fields).length)
  )
    ticket.service_fields = { ...draft.service_fields };
  return {
    unit_id: unit.id,
    ticket,
    requestKey,
    ...(draft.service_id ? { service_id: id(draft.service_id) } : {}),
    ...(draft.conversation_id
      ? { conversation_id: id(draft.conversation_id) }
      : {}),
  };
}
export function updateTicketDraft(draft, record, customerMaster = false) {
  if (!record?.permissions?.update || record.unit_id !== id(draft.unit_id))
    throw new TypeError('Record not editable');
  return {
    ticketId: record.id,
    expected_lock_version: record.lock_version,
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
      ...(Object.hasOwn(draft, 'ticket_type_id')
        ? {
            ticket_type_id: draft.ticket_type_id
              ? id(draft.ticket_type_id)
              : null,
          }
        : {}),
      ...(Object.hasOwn(draft, 'subcategory_id')
        ? {
            subcategory_id: draft.subcategory_id
              ? id(draft.subcategory_id)
              : null,
          }
        : {}),
      ...(Object.hasOwn(draft, 'contract_id') &&
      Object.hasOwn(record, 'contract')
        ? { contract_id: draft.contract_id ? id(draft.contract_id) : null }
        : {}),
      ...(Object.hasOwn(draft, 'service_fields') &&
      Object.hasOwn(record, 'service_fields')
        ? { service_fields: { ...draft.service_fields } }
        : {}),
    },
  };
}
export function newRequestKey() {
  if (typeof globalThis.crypto?.randomUUID === 'function')
    return globalThis.crypto.randomUUID();
  if (typeof globalThis.crypto?.getRandomValues !== 'function')
    throw new TypeError('Secure request key unavailable');
  const bytes = globalThis.crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, value => value.toString(16).padStart(2, '0')).join(
    ''
  );
}
export async function ticketFileFingerprints(files) {
  if (!Array.isArray(files) || files.length > 5)
    throw new TypeError('Invalid ticket attachments');
  if (!files.length) return [];
  if (!globalThis.crypto?.subtle?.digest)
    throw new TypeError('Secure file fingerprint unavailable');
  return Promise.all(
    files.map(async file => {
      if (
        !file ||
        typeof file.name !== 'string' ||
        file.name.length > 255 ||
        file.size <= 0 ||
        file.size > 20 * 1024 * 1024 ||
        typeof file.arrayBuffer !== 'function'
      )
        throw new TypeError('Invalid ticket attachment');
      const digest = await globalThis.crypto.subtle.digest(
        'SHA-256',
        await file.arrayBuffer()
      );
      return {
        name: file.name,
        size: file.size,
        sha256: Array.from(new Uint8Array(digest), value =>
          value.toString(16).padStart(2, '0')
        ).join(''),
      };
    })
  );
}
