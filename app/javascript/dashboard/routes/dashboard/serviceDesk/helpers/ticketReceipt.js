import { canonicalId } from './access.js';

// Only display an identifier belonging to a persisted, authorized ticket.
// No local sequence, guessed prefix, or protocol before the server readback.
export function ticketProtocol(ticket) {
  const id = canonicalId(ticket?.id);
  if (!id) return '';
  return typeof ticket.number === 'string' && ticket.number.trim()
    ? ticket.number.trim()
    : id;
}

export function confirmedCreationTicket(receipt, state, accountId, userId) {
  const context = state.context;
  const ticket = receipt?.ticket;
  if (
    !ticket ||
    state.status !== 'ready' ||
    context?.available !== true ||
    receipt.account_id !== canonicalId(accountId) ||
    receipt.user_id !== canonicalId(userId) ||
    receipt.account_id !== context.account_id ||
    receipt.user_id !== context.user_id ||
    ticket.account_id !== context.account_id ||
    ticket.permissions?.show !== true ||
    !context.units.some(unit => unit.id === ticket.unit_id) ||
    !ticketProtocol(ticket)
  )
    return null;
  return ticket;
}

// A deliberate manual selection always wins over automatic routing.
export function selectTicketAssignment(draft, names, field, selected) {
  if (!['assignee', 'queue', 'team'].includes(field))
    throw new TypeError('Unsupported assignment field');
  names[field] = selected;
  if (draft[`${field}_id`]) draft.use_channel_routing = false;
}

// Never display an agent that the request builder will silently omit.
export function selectAutomaticRouting(draft, names, enabled) {
  draft.use_channel_routing = enabled === true;
  if (!draft.use_channel_routing) return;
  ['assignee', 'queue', 'team'].forEach(field => {
    draft[`${field}_id`] = '';
    names[field] = null;
  });
}
