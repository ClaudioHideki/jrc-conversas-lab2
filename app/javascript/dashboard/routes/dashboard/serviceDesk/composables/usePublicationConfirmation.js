import { ref, watch } from 'vue';
import { canonicalId } from '../helpers/access';

export function usePublicationConfirmation(session, route, result) {
  const confirmation = ref(null);
  const authorized = publication => {
    const context = session.state.context;
    const ticket = result.value.record;
    return (
      session.state.status === 'ready' &&
      publication.account_id === context?.account_id &&
      publication.account_id === session.accountId.value &&
      publication.account_id === canonicalId(route.params.accountId) &&
      publication.ticket_id === canonicalId(route.params.ticketId) &&
      context.units.some(unit => unit.id === publication.unit_id) &&
      ticket?.id === publication.ticket_id &&
      ticket.account_id === publication.account_id &&
      ticket.unit_id === publication.unit_id &&
      ticket.permissions?.view_notes === true &&
      ticket.permissions?.add_note === true
    );
  };
  const accept = publication => {
    if (
      publication?.operation !== 'add_interaction' ||
      !canonicalId(publication.result_id) ||
      !['saved', 'published_blocked'].includes(publication.outcome) ||
      !authorized(publication)
    )
      return;
    confirmation.value = {
      account_id: publication.account_id,
      unit_id: publication.unit_id,
      ticket_id: publication.ticket_id,
      result_id: publication.result_id,
      outcome: publication.outcome,
    };
  };
  watch(
    [
      () => route.params.accountId,
      () => route.params.ticketId,
      () => session.accountId.value,
      () => session.state.context,
      () => session.state.status,
    ],
    () => {
      confirmation.value = null;
    },
    { flush: 'sync' }
  );
  watch(
    [
      () => result.value.status,
      () => result.value.record,
      () => result.value.record?.permissions?.view_notes,
      () => result.value.record?.permissions?.add_note,
    ],
    () => {
      const current = result.value;
      if (!confirmation.value) return;
      if (['idle', 'loading'].includes(current.status)) return;
      if (current.status !== 'ready' || !authorized(confirmation.value))
        confirmation.value = null;
    }
  );
  return { confirmation, accept };
}
