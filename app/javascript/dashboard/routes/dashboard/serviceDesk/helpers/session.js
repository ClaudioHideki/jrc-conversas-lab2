import { canonicalId, canRead } from './access.js';
import { decodeContext, decodeCollection, decodeTicket, ContractError } from './contracts.js';
import { normalizeQuery, queryWithinContext, QueryError } from './query.js';
export const createResourceState = () => ({ status: 'idle', items: [], record: null, meta: null });
export const createSessionState = () => ({ status: 'idle', context: null, resources: {} });
export function errorStatus(error, detail = false) {
  if (error instanceof ContractError)
    return 'invalid_contract';
  if (error instanceof QueryError || error instanceof TypeError)
    return 'invalid_request';
  const status = error?.response?.status;
  if (status === 401)
    return 'unauthenticated';
  if (status === 403)
    return 'denied';
  if (status === 404)
    return detail || error?.response?.data?.code === 'not_found' ? 'not_found' : 'pending';
  if ([405, 501].includes(status))
    return 'pending';
  return 'error';
}
// Instance-local state: no account-shared Vuex cache, module singleton or storage.
export function createServiceDeskSession(client, state = createSessionState()) {
  let generation = 0;
  let identity = null;
  const controllers = new Map();
  const sequences = new Map();
  const cancel = key => { controllers.get(key)?.abort(); controllers.delete(key); };
  const clear = status => {
    generation += 1;
    controllers.forEach(controller => controller.abort());
    controllers.clear();
    sequences.clear();
    state.status = status;
    state.context = null;
    state.resources = {};
  };
  const resetResource = (key, status = 'idle') => {
    cancel(key);
    sequences.set(key, (sequences.get(key) || 0) + 1);
    state.resources[key] = { ...createResourceState(), status };
  };
  const resource = key => state.resources[key] || createResourceState();
  const start = async next => {
    clear('idle');
    identity = { accountId: canonicalId(next.accountId), userId: canonicalId(next.userId), enabled: next.enabled === true };
    if (!identity.enabled) {
      state.status = 'disabled';
      return;
    }
    if (!identity.accountId || !identity.userId) {
      state.status = 'denied';
      return;
    }
    state.status = 'loading';
    const epoch = generation;
    const controller = new AbortController();
    controllers.set('context', controller);
    try {
      const payload = await client.context(identity.accountId, controller.signal);
      if (epoch !== generation)
        return;
      const decoded = decodeContext(payload, identity);
      if (!decoded.available || !decoded.units.length || decoded.capabilities?.module?.index !== true) {
        clear('denied');
        return;
      }
      state.context = decoded;
      state.status = 'ready';
    }
    catch (error) {
      if (epoch !== generation)
        return;
      clear(errorStatus(error));
    }
    finally {
      if (epoch === generation)
        controllers.delete('context');
    }
  };
  const load = async (key, resourceName, query = {}, ticketId = null) => {
    resetResource(key);
    if (state.status !== 'ready' || !identity?.enabled) {
      state.resources[key].status = state.status === 'ready' ? 'denied' : state.status;
      return;
    }
    if (!canRead(state.context, resourceName)) {
      state.resources[key].status = 'denied';
      return;
    }
    let request;
    try {
      request = normalizeQuery(query);
      if (!queryWithinContext(request, state.context))
        throw new QueryError('Unauthorized scope selector');
      if (ticketId !== null && !canonicalId(ticketId))
        throw new QueryError('Invalid ticket');
    }
    catch (error) {
      state.resources[key].status = errorStatus(error);
      return;
    }
    const epoch = generation;
    const seq = sequences.get(key);
    const controller = new AbortController();
    controllers.set(key, controller);
    state.resources[key].status = 'loading';
    try {
      const payload = ticketId !== null
        ? await client.ticket(identity.accountId, canonicalId(ticketId), controller.signal)
        : await client.list(identity.accountId, resourceName, request, controller.signal);
      if (epoch !== generation || seq !== sequences.get(key))
        return;
      if (ticketId !== null) {
        state.resources[key] = { ...createResourceState(), status: 'ready', record: decodeTicket(payload, state.context, canonicalId(ticketId)) };
      }
      else {
        const decoded = decodeCollection(payload, state.context, resourceName, request);
        state.resources[key] = { ...createResourceState(), ...decoded, status: decoded.items.length ? 'ready' : 'empty' };
      }
    }
    catch (error) {
      if (epoch !== generation || seq !== sequences.get(key))
        return;
      const status = errorStatus(error, ticketId !== null);
      if (['denied', 'unauthenticated', 'invalid_contract'].includes(status))
        clear(status);
      else
        state.resources[key] = { ...createResourceState(), status };
    }
    finally {
      if (epoch === generation && seq === sequences.get(key))
        controllers.delete(key);
    }
  };
  const revalidate = async () => {
    if (!identity?.enabled || state.status !== 'ready') return;
    const epoch = generation;
    cancel('revalidate');
    const controller = new AbortController(); controllers.set('revalidate', controller);
    try {
      const payload = await client.context(identity.accountId, controller.signal);
      if (epoch !== generation || controller.signal.aborted) return;
      const next = decodeContext(payload, identity);
      if (!next.available || !next.units.length || next.capabilities?.module?.index !== true) { clear('denied'); return; }
      // Clear records/drafts and fetch again if the authorization projection changed.
      if (JSON.stringify(next) !== JSON.stringify(state.context)) await start(identity);
    } catch (error) {
      if (epoch === generation && !controller.signal.aborted) clear(errorStatus(error));
    } finally {
      if (epoch === generation) controllers.delete('revalidate');
    }
  };
  return { state, start, load, revalidate, resource, resetResource, retry: () => identity && start(identity), dispose: () => clear('idle') };
}
