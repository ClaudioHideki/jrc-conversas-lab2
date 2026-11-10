import { canAct } from './access';

// Self-assignment uses the native AccountUser, not the unrelated User ID.
export function selfAssignment(context, ticket) {
  if (
    context?.available !== true ||
    context.account_id !== ticket?.account_id ||
    !canAct(ticket, 'assign') ||
    ['closed', 'cancelled'].includes(ticket.status_phase)
  )
    return null;
  const member = context.units.find(
    unit => unit.id === ticket.unit_id
  )?.self_assignee;
  return member && member.id !== ticket.assignee?.id ? member : null;
}
