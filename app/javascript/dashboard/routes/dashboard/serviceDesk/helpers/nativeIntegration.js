import { canonicalId, createServiceDeskGuard, canRead } from './access.js';
import { ContractError, decodeContext } from './contracts.js';
import { SERVICE_DESK_ROUTES, serviceDeskRouteName } from '../routeDefinitions.js';
const requireValue = condition => { if (!condition) throw new ContractError(); };
const id = value => { const parsed = canonicalId(value); requireValue(!!parsed); return parsed; };
export function moduleAccessible(context) {
  return context?.available === true && context.capabilities?.module?.index === true && Array.isArray(context.units) && context.units.length > 0;
}
export function screenAccessible(context, definition) {
  if (!moduleAccessible(context) || !definition) return false;
  if (definition.key === 'overview') return canRead(context, 'dashboard');
  if (definition.key === 'new') return context.units.some(unit => unit.permissions.create_ticket === true);
  if (['detail', 'edit', 'tickets', 'mine'].includes(definition.key)) return canRead(context, 'tickets');
  return canRead(context, definition.resource || definition.key);
}
export function landingScreen(context) {
  return ['overview', 'tickets', 'settings', 'queues', 'units'].find(key => screenAccessible(context, SERVICE_DESK_ROUTES.find(row => row.key === key))) || null;
}
export function createIntegratedGuard(store, refreshAccount, refreshContext) {
  const flagGuard = createServiceDeskGuard(store, refreshAccount);
  let turn = 0;
  return async to => {
    const epoch = ++turn;
    const accountId = canonicalId(to.params.accountId);
    const userId = canonicalId(store.getters.getCurrentUserID);
    if (!accountId || !userId) return false;
    const denied = reason => ({ name: 'jrc_service_desk_denied', params: { accountId }, query: { reason } });
    try {
      const permitted = await flagGuard(to);
      if (epoch !== turn || canonicalId(store.getters.getCurrentUserID) !== userId) return false;
      if (permitted !== true) return permitted;
      const payload = await refreshContext(accountId);
      if (epoch !== turn || canonicalId(store.getters.getCurrentUserID) !== userId) return false;
      const context = decodeContext(payload, { accountId, userId });
      const definition = SERVICE_DESK_ROUTES.find(row => row.key === (to.meta?.serviceDeskScreen || 'overview'));
      return screenAccessible(context, definition) ? true : denied('denied');
    } catch (error) {
      if (epoch !== turn || canonicalId(store.getters.getCurrentUserID) !== userId) return false;
      return denied(error?.response?.status === 403 ? 'denied' : error?.response?.status === 401 ? 'unauthenticated' : 'error');
    }
  };
}
export function createNavigationAccess(client, state = { visible: false, route: null, context: null, status: 'idle' }) {
  let epoch = 0; let controller;
  const clear = status => { epoch += 1; controller?.abort(); state.visible = false; state.route = null; state.context = null; state.status = status; };
  const refresh = async identity => {
    clear('loading');
    const accountId = canonicalId(identity.accountId), userId = canonicalId(identity.userId);
    if (identity.enabled !== true || !accountId || !userId) { state.status = 'disabled'; return; }
    const turn = epoch; controller = new AbortController();
    try {
      const payload = await client.context(accountId, controller.signal);
      if (turn !== epoch) return;
      const context = decodeContext(payload, { accountId, userId });
      const landing = landingScreen(context);
      if (!moduleAccessible(context) || !landing) { clear('denied'); return; }
      state.context = context; state.route = serviceDeskRouteName(landing); state.visible = true; state.status = 'ready';
    } catch (error) {
      if (turn === epoch) clear(error?.response?.status === 403 ? 'denied' : 'unavailable');
    }
  };
  return { state, refresh, clear, dispose: () => clear('idle') };
}
const ticketScope = (payload, context, ticket) => {
  requireValue(payload?.contract_version === 1 && id(payload.account_id) === context.account_id);
  requireValue(id(payload.ticket_id) === ticket.id && id(payload.unit_id) === ticket.unit_id);
  requireValue(context.units.some(unit => unit.id === ticket.unit_id));
};
export function decodeConversationNavigation(payload, context, ticket, linkId) {
  ticketScope(payload, context, ticket);
  requireValue(id(payload.link_id) === id(linkId));
  const displayId = id(payload.conversation_display_id), conversationId = id(payload.conversation_id);
  requireValue(payload.route?.name === 'inbox_conversation');
  requireValue(id(payload.route.params?.accountId) === context.account_id && id(payload.route.params?.conversation_id) === displayId);
  // Never forward a backend-provided URL, redirect or arbitrary route/query.
  return { conversation_id: conversationId, route: { name: 'inbox_conversation', params: { accountId: context.account_id, conversation_id: displayId } } };
}
export function decodeCustomerContext(payload, context, ticket) {
  ticketScope(payload, context, ticket);
  const named = row => {
    requireValue(row && id(row.account_id) === context.account_id && typeof row.name === 'string');
    return { id: id(row.id), name: row.name };
  };
  const contact = named(payload.contact);
  requireValue(!ticket.requester || contact.id === ticket.requester.id);
  requireValue(['available', 'not_linked', 'not_available'].includes(payload.company_state));
  requireValue((payload.company_state === 'available') === (payload.company !== null));
  return { contact, company: payload.company ? named(payload.company) : null, company_state: payload.company_state };
}
