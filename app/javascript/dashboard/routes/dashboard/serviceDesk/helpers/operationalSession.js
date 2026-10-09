import { canonicalId, canAct, canRead } from './access.js';
import { decodeTicket, ContractError } from './contracts.js';
import {
  decodeDashboard,
  decodeRelated,
  decodeAcknowledgement,
  decodeRelatedItem,
  verifyWrittenFields,
  verifyOpeningAttachments,
} from './operationalContracts.js';
import { normalizeQuery, queryWithinContext } from './query.js';
import { errorStatus } from './session.js';
const ACTION_PERMISSION = {
  update: 'update',
  assign: 'assign',
  transfer: 'transfer',
  work_status: 'change_work_status',
  add_note: 'add_note',
  link_conversation: 'link_conversation',
};
export const createOperationalState = () => ({
  reads: {},
  writes: {},
  revision: 0,
  notice: null,
});
export function createOperationalSession(
  client,
  base,
  state = createOperationalState()
) {
  let epoch = 0;
  const controllers = new Map();
  const sequences = new Map();
  const intents = new Map();
  const clear = () => {
    epoch += 1;
    controllers.forEach(c => c.abort());
    controllers.clear();
    sequences.clear();
    intents.clear();
    state.reads = {};
    state.writes = {};
    state.notice = null;
  };
  const cancel = key => {
    controllers.get(key)?.abort();
    controllers.delete(key);
    sequences.set(key, (sequences.get(key) || 0) + 1);
    if (state.writes[key]?.status === 'saving')
      state.writes[key] = { status: 'interrupted', ticket: null };
  };
  const current = () => {
    if (base.state.status !== 'ready' || base.state.context?.available !== true)
      throw new TypeError('No confirmed context');
    return base.state.context;
  };
  const revoke = status => {
    clear();
    base.dispose();
    base.state.status = status;
  };
  const read = async (key, kind, { ticket = null, query = {} } = {}) => {
    cancel(key);
    state.reads[key] = { status: 'loading', data: null };
    const turn = epoch,
      seq = sequences.get(key),
      controller = new AbortController();
    controllers.set(key, controller);
    try {
      const context = current(),
        normalized = normalizeQuery(query);
      if (
        !queryWithinContext(normalized, context) ||
        !canRead(context, 'tickets')
      )
        throw new TypeError('Invalid scope');
      if (kind === 'dashboard' && !canRead(context, 'dashboard'))
        throw new TypeError('Dashboard not permitted');
      if (kind !== 'dashboard' && (!ticket || !canAct(ticket, 'show')))
        throw new TypeError('Ticket unavailable');
      const permission = {
        notes: 'view_notes',
        events: 'view_history',
        sla: 'view_sla',
        conversations: 'view_conversations',
        status_options: 'change_work_status',
      }[kind];
      if (permission && ticket.permissions[permission] === false) {
        state.reads[key] = { status: 'denied', data: null };
        return null;
      }
      const payload =
        kind === 'dashboard'
          ? await client.dashboard(
              context.account_id,
              normalized,
              controller.signal
            )
          : await client.related(
              context.account_id,
              ticket.id,
              kind,
              normalized,
              controller.signal
            );
      if (turn !== epoch || seq !== sequences.get(key) || current() !== context)
        return null;
      const data =
        kind === 'dashboard'
          ? decodeDashboard(payload, context, normalized)
          : decodeRelated(payload, context, ticket, kind, normalized);
      state.reads[key] = {
        status: kind === 'dashboard' || data.items.length ? 'ready' : 'empty',
        data,
      };
      return data;
    } catch (error) {
      if (turn !== epoch || seq !== sequences.get(key)) return null;
      const status = errorStatus(error, kind !== 'dashboard');
      if (['denied', 'unauthenticated', 'invalid_contract'].includes(status))
        revoke(status);
      else state.reads[key] = { status, data: null };
      return null;
    } finally {
      if (turn === epoch && seq === sequences.get(key)) controllers.delete(key);
    }
  };
  const write = async (key, action, payload, ticket = null) => {
    if (state.writes[key]?.status === 'saving') return null;
    cancel(key);
    const turn = epoch,
      seq = sequences.get(key),
      controller = new AbortController();
    controllers.set(key, controller);
    state.notice = null;
    state.writes[key] = { status: 'saving', ticket: null };
    let accepted = false;
    try {
      const context = current();
      if (action === 'create') {
        if (
          !context.units.some(
            unit =>
              unit.id === canonicalId(payload.unit_id) &&
              unit.permissions.create_ticket === true
          )
        )
          throw new TypeError('Unit not authorized');
      } else if (
        !Object.hasOwn(ACTION_PERMISSION, action) ||
        !ticket ||
        ticket.id !== canonicalId(payload.ticketId) ||
        !(
          canAct(ticket, ACTION_PERMISSION[action]) ||
          (action === 'update' &&
            canAct(ticket, 'change_priority') &&
            Object.keys(payload.ticket || {}).length === 1 &&
            Object.hasOwn(payload.ticket, 'priority_id'))
        )
      ) {
        throw new TypeError('Action not authorized');
      }
      if (['create', 'add_note'].includes(action)) {
        const fingerprint = JSON.stringify({ action, payload });
        if (intents.has(key) && intents.get(key) !== fingerprint) {
          state.writes[key] = { status: 'intent_changed', ticket: null };
          return null;
        }
        intents.set(key, fingerprint);
      }
      const ack = await client[action](
        context.account_id,
        payload,
        controller.signal
      );
      if (turn !== epoch || seq !== sequences.get(key) || current() !== context)
        return null;
      const ticketId = decodeAcknowledgement(
        ack,
        context,
        action,
        action === 'create' ? null : ticket.id
      );
      accepted = true;
      // No optimistic state: re-read persisted data, even when POST/PATCH returned 2xx.
      const result = await client.ticket(
        context.account_id,
        ticketId,
        controller.signal
      );
      if (turn !== epoch || seq !== sequences.get(key) || current() !== context)
        return null;
      const confirmed = verifyWrittenFields(
        action,
        payload,
        decodeTicket(result, context, ticketId)
      );
      const relation =
        action === 'add_note'
          ? 'notes'
          : action === 'link_conversation' ||
              (action === 'create' && payload.conversation_id)
            ? 'conversations'
            : null;
      if (relation) {
        const recordId = canonicalId(ack.result_id);
        if (!recordId) throw new ContractError();
        const relatedPayload = await client.relatedItem(
          context.account_id,
          ticketId,
          relation,
          recordId,
          controller.signal
        );
        if (
          turn !== epoch ||
          seq !== sequences.get(key) ||
          current() !== context
        )
          return null;
        const related = decodeRelatedItem(
          relatedPayload,
          context,
          confirmed,
          relation,
          recordId
        );
        if (relation === 'notes' && related.body !== payload.note.body)
          throw new ContractError();
        if (
          relation === 'conversations' &&
          related.conversation_id !== canonicalId(payload.conversation_id)
        )
          throw new ContractError();
      }
      if (action === 'create' && payload.files?.length) {
        const noteId = canonicalId(ack.opening_note_id);
        if (!noteId) throw new ContractError();
        const relatedPayload = await client.relatedItem(
          context.account_id,
          ticketId,
          'notes',
          noteId,
          controller.signal
        );
        if (
          turn !== epoch ||
          seq !== sequences.get(key) ||
          current() !== context
        )
          return null;
        const note = decodeRelatedItem(
          relatedPayload,
          context,
          confirmed,
          'notes',
          noteId
        );
        verifyOpeningAttachments(note, payload);
      }
      state.writes[key] = { status: 'confirmed', ticket: confirmed };
      state.revision += 1;
      intents.delete(key);
      return confirmed;
    } catch (error) {
      if (turn !== epoch || seq !== sequences.get(key)) return null;
      const status = error?.response?.status;
      if (accepted) {
        state.writes[key] = { status: 'readback_pending', ticket: null };
        // Clear stale protected data; a successful assignment can legitimately
        // remove the actor's record visibility. Never undo or regrant it in Vue.
        if ([401, 403, 404].includes(status)) {
          base.dispose();
          base.state.status = status === 401 ? 'unauthenticated' : 'denied';
        }
        // Only a non-sensitive outcome survives losing record visibility.
        // No record, unit or account data is restored by this notice.
        state.notice = 'readback_pending';
      } else if ([401, 403].includes(status))
        revoke(status === 401 ? 'unauthenticated' : 'denied');
      else {
        state.writes[key] = {
          status:
            status === 409
              ? 'conflict'
              : status === 422
                ? 'invalid_input'
                : error instanceof ContractError
                  ? 'invalid_contract'
                  : 'error',
          ticket: null,
        };
        if (status === 422) intents.delete(key); // Rejected request did not commit.
      }
      return null;
    } finally {
      if (turn === epoch && seq === sequences.get(key)) controllers.delete(key);
    }
  };
  return {
    state,
    read,
    write,
    clear,
    cancel,
    resource: key => state.reads[key] || { status: 'idle', data: null },
    mutation: key => state.writes[key] || { status: 'idle', ticket: null },
  };
}
