// Synthetic transports are TEST ONLY. No service or screen imports this file.
import { moduleAccessible, screenAccessible, landingScreen, createIntegratedGuard, createNavigationAccess, decodeConversationNavigation, decodeCustomerContext } from '../helpers/nativeIntegration.js';
import { createServiceDeskNativeClient } from '../../../../api/serviceDeskNativeClient.js';
import { createServiceDeskOperationsClient } from '../../../../api/serviceDeskOperationsClient.js';
import { decodeContext, decodeTicket, ContractError } from '../helpers/contracts.js';
import { createServiceDeskSession } from '../helpers/session.js';
import { createOperationalSession } from '../helpers/operationalSession.js';
import { SERVICE_DESK_ROUTES } from '../routeDefinitions.js';
import { contextPayload, identity, ticket, detail, deferred, httpError, fakeClient } from './fixtures.js';
const context = (overrides = {}) => decodeContext(contextPayload(overrides), identity);
const row = () => decodeTicket(detail(ticket({ lock_version: 0 })), context(), '20');
const screen = key => SERVICE_DESK_ROUTES.find(r => r.key === key);
const target = (key = 'tickets', account = '1') => ({ params: { accountId: account }, meta: { serviceDeskScreen: key } });
function guardSetup(payload = () => contextPayload()) {
  const calls = []; const store = { getters: { getCurrentUserID: '7', 'accounts/isFeatureEnabledonAccount': () => true } };
  const guard = createIntegratedGuard(store, async id => { calls.push(['account', id]); return { id, features: { jrc_service_desk: true } }; }, async id => { calls.push(['context', id]); return payload(id); });
  return { guard, calls, store };
}
const navigation = overrides => ({ contract_version: 1, account_id: '1', unit_id: '10', ticket_id: '20', link_id: '50',
  conversation_id: '900', conversation_display_id: '12', route: { name: 'inbox_conversation', params: { accountId: '1', conversation_id: '12' } }, ...overrides });
const customer = overrides => ({ contract_version: 1, account_id: '1', unit_id: '10', ticket_id: '20',
  contact: { id: '33', account_id: '1', name: 'Fixture contact' }, company: null, company_state: 'not_linked', ...overrides });
export function registerCp5Cases(test, assert) {
  test('module entry requires affirmative backend capability, not mere feature or local admin', () => {
    assert.equal(moduleAccessible(null), false);
    assert.equal(moduleAccessible(context()), true);
    assert.equal(moduleAccessible(context({ capabilities: {} })), false);
    assert.equal(moduleAccessible(context({ capabilities: { module: { index: false } } })), false);
    assert.equal(moduleAccessible(context({ units: [] })), false);
  });
  test('landing follows only backend resources, dashboard is not automatic', () => {
    assert.equal(landingScreen(context()), 'overview');
    assert.equal(landingScreen(context({ capabilities: { module: { index: true }, tickets: { index: true } } })), 'tickets');
    assert.equal(landingScreen(context({ capabilities: { module: { index: true }, settings: { index: true } } })), 'settings');
    assert.equal(landingScreen(context({ capabilities: { module: { index: true } }, units: contextPayload().units.map(u => ({ ...u, permissions: {} })) })), null);
  });
  for (const definition of SERVICE_DESK_ROUTES) test(`screen ${definition.key}: no context or explicit denial cannot render records`, () => {
    assert.equal(screenAccessible(null, definition), false);
    assert.equal(screenAccessible(context({ capabilities: {}, units: [] }), definition), false);
  });
  test('detail/edit use ticket access; creation needs an explicit allowed unit', () => {
    assert.equal(screenAccessible(context(), screen('detail')), true);
    assert.equal(screenAccessible(context(), screen('edit')), true);
    assert.equal(screenAccessible(context({ units: contextPayload().units.map(u => ({ ...u, permissions: {} })) }), screen('new')), false);
  });
  test('deep link refreshes target Account and the native scoped ui_context', async () => {
    const { guard, calls } = guardSetup(); assert.equal(await guard(target()), true);
    assert.deepEqual(calls, [['account', '1'], ['context', '1']]);
  });
  test('a native admin identifier never overrides a denied backend context', async () => {
    const { guard } = guardSetup(() => contextPayload({ capabilities: {} }));
    assert.deepEqual(await guard(target()), { name: 'jrc_service_desk_denied', params: { accountId: '1' }, query: { reason: 'denied' } });
  });
  for (const code of [401, 403, 404, 500]) test(`guard HTTP ${code} is unavailable/denied, never a success`, async () => {
    const { guard } = guardSetup(() => { throw httpError(code); });
    const result = await guard(target()); assert.equal(result.name, 'jrc_service_desk_denied');
    assert.equal(result.query.reason, code === 401 ? 'unauthenticated' : code === 403 ? 'denied' : 'error');
  });
  test('wrong Account or wrong user in context is denied', async () => {
    for (const update of [{ account_id: '2' }, { user_id: '8' }]) {
      assert.equal((await guardSetup(() => contextPayload(update)).guard(target())).name, 'jrc_service_desk_denied');
    }
  });
  test('identity changed while checking a deep link invalidates old response', async () => {
    const wait = deferred(), { guard, store } = guardSetup(() => wait.promise);
    const task = guard(target()); await Promise.resolve(); await Promise.resolve();
    store.getters.getCurrentUserID = '8'; wait.resolve(contextPayload()); assert.equal(await task, false);
  });
  test('flag false does not query operational context and uses native home', async () => {
    let calls = 0; const store = { getters: { getCurrentUserID: '7', 'accounts/isFeatureEnabledonAccount': () => false } };
    const guard = createIntegratedGuard(store, async id => ({ id, features: { jrc_service_desk: false } }), () => { calls += 1; });
    assert.equal((await guard(target())).name, 'home'); assert.equal(calls, 0);
  });
  test('sidebar stays absent until backend context resolves', async () => {
    const wait = deferred(); const access = createNavigationAccess({ context: () => wait.promise });
    const task = access.refresh(identity); assert.equal(access.state.visible, false);
    wait.resolve(contextPayload()); await task;
    assert.equal(access.state.visible, true); assert.equal(access.state.route, 'jrc_service_desk_overview');
  });
  test('sidebar flag false never calls ui_context', async () => {
    let calls = 0; const access = createNavigationAccess({ context: () => { calls += 1; } });
    await access.refresh({ ...identity, enabled: false }); assert.equal(calls, 0); assert.equal(access.state.visible, false);
  });
  test('sidebar failure after prior success erases protected context', async () => {
    let failed = false; const access = createNavigationAccess({ context: async () => { if (failed) throw httpError(403); return contextPayload(); } });
    await access.refresh(identity); failed = true; await access.refresh(identity);
    assert.equal(access.state.visible, false); assert.equal(access.state.context, null); assert.equal(access.state.status, 'denied');
  });
  test('sidebar Account switch cannot be repopulated by older response', async () => {
    const wait = deferred(); const access = createNavigationAccess({ context: () => wait.promise });
    const task = access.refresh(identity); await access.refresh({ accountId: '2', userId: '7', enabled: false });
    wait.resolve(contextPayload()); await task; assert.equal(access.state.context, null); assert.equal(access.state.visible, false);
  });
  test('authoritative revalidation removes data on grant revocation', async () => {
    let value = contextPayload(); const session = createServiceDeskSession(fakeClient({ context: async () => value }));
    await session.start(identity); await session.load('tickets', 'tickets');
    assert.equal(session.resource('tickets').items.length, 1);
    value = contextPayload({ units: [] }); await session.revalidate();
    assert.equal(session.state.status, 'denied'); assert.deepEqual(session.state.resources, {});
  });
  test('authoritative revalidation removes data when action capabilities change', async () => {
    let value = contextPayload(); const session = createServiceDeskSession(fakeClient({ context: async () => value }));
    await session.start(identity); await session.load('tickets', 'tickets');
    value = contextPayload({ effective_permissions: ['jrc_service_desk_module_view'] }); await session.revalidate();
    assert.equal(session.state.status, 'ready'); assert.deepEqual(session.state.resources, {});
  });
  test('server feature revocation and communication failure both clear stale session', async () => {
    for (const status of [401, 403, 404, 500]) {
      let fail = false; const session = createServiceDeskSession(fakeClient({ context: async () => { if (fail) throw httpError(status); return contextPayload(); } }));
      await session.start(identity); fail = true; await session.revalidate(); assert.equal(session.state.context, null);
    }
  });
  test('Account switch cancels stale revalidation response', async () => {
    let wait = null; const session = createServiceDeskSession(fakeClient({ context: async () => wait ? wait.promise : contextPayload() }));
    await session.start(identity); wait = deferred(); const task = session.revalidate();
    await session.start({ ...identity, accountId: '2', enabled: false }); wait.resolve(contextPayload()); await task;
    assert.equal(session.state.status, 'disabled'); assert.equal(session.state.context, null);
  });
  test('conversation uses display_id for the native route, not its database primary key', () => {
    assert.deepEqual(decodeConversationNavigation(navigation(), context(), row(), '50'), { conversation_id: '900', route: { name: 'inbox_conversation', params: { accountId: '1', conversation_id: '12' } } });
  });
  for (const changes of [{ account_id: '2' }, { unit_id: '11' }, { ticket_id: '21' }, { link_id: '51' }, { conversation_display_id: '900' }, { route: { name: 'home' } }]) test(`conversation rejects tampered context ${JSON.stringify(changes)}`, () => {
    assert.throws(() => decodeConversationNavigation(navigation(changes), context(), row(), '50'), ContractError);
  });
  test('route response strips arbitrary URLs, return paths and external navigation', () => {
    const value = navigation({ url: 'https://example.invalid/', redirect: '/admin' }); value.route.query = { url: '/admin' };
    assert.deepEqual(Object.keys(decodeConversationNavigation(value, context(), row(), '50').route).sort(), ['name', 'params']);
  });
  test('customer response is a minimal native projection, not another contact or operator', () => {
    const input = customer(); input.contact.email = 'private@test.invalid'; input.contact.secret = 'forbidden';
    const result = decodeCustomerContext(input, context(), row());
    assert.deepEqual(result.contact, { id: '33', name: 'Fixture contact' }); assert.equal(result.company, null);
  });
  for (const changes of [{ account_id: '2' }, { unit_id: '11' }, { ticket_id: '21' }, { contact: { id: '99', account_id: '1', name: 'Wrong requester' } }, { contact: { id: '33', account_id: '2', name: 'Foreign' } }, { company_state: 'available', company: { id: '5', account_id: '2', name: 'Foreign company' } }]) test(`customer rejects foreign projection ${JSON.stringify(changes)}`, () => {
    assert.throws(() => decodeCustomerContext(customer(changes), context(), row()), ContractError);
  });
  test('customer Company uses its native ID and Account rather than operator ID', () => {
    const result = decodeCustomerContext(customer({ company_state: 'available', company: { id: '501', account_id: '1', name: 'Native customer company' } }), context(), row());
    assert.equal(result.company.id, '501');
  });
  test('native lookup client is GET-only, scoped and uses separate navigation authorization', async () => {
    const calls = []; const client = createServiceDeskNativeClient({ get: async (url, options) => { calls.push([url, options]); return { data: {} }; } });
    await client.customer('1', '20'); await client.conversation('1', '20', '50');
    assert.equal(calls[0][0], '/api/v1/accounts/1/jrc_service_desk/tickets/20/customer_context');
    assert.equal(calls[1][0], '/api/v1/accounts/1/jrc_service_desk/tickets/20/conversations/50/navigation');
    assert.equal(calls[0][1].timeout, 15000); assert.equal(client.create, undefined);
  });
  for (const value of ['../2', '1?admin=true', '0', 'abc', {}, ['2']]) test(`native client rejects injected identifier ${JSON.stringify(value)}`, () => {
    const client = createServiceDeskNativeClient({ get: () => { throw new Error('must not call'); } });
    assert.throws(() => client.conversation('1', '20', value), TypeError);
  });
  test('transfer is a distinct endpoint and acknowledgement, not an assign alias', async () => {
    const calls = []; const client = createServiceDeskOperationsClient({ post: async (url, body) => { calls.push([url, body]); return { data: {} }; } });
    await client.transfer('1', { ticketId: '20', assignment: { queue_id: '4' }, expected_lock_version: 0 });
    assert.equal(calls[0][0], '/api/v1/accounts/1/jrc_service_desk/tickets/20/transfer');
  });
  test('priority-only action is separate from data edit and confirms with GET', async () => {
    const ctx = context(), value = row(); value.permissions.update = false; value.permissions.change_priority = true;
    const base = { state: { status: 'ready', context: ctx }, dispose() { this.state.context = null; } }; let calls = 0;
    const ops = createOperationalSession({ update: async () => { calls += 1; return { contract_version: 1, account_id: '1', ticket_id: '20', operation: 'update', applied: true }; }, ticket: async () => detail(ticket({ priority: { id: '8', name: 'Fixture P' } })) }, base);
    const result = await ops.write('priority', 'update', { ticketId: '20', ticket: { priority_id: '8' }, expected_lock_version: 0 }, value);
    assert.equal(calls, 1); assert.equal(result.priority.id, '8');
    await ops.write('mixed', 'update', { ticketId: '20', ticket: { priority_id: '8', title: 'Not authorized' }, expected_lock_version: 0 }, value);
    assert.equal(calls, 1); assert.notEqual(ops.mutation('mixed').status, 'confirmed');
  });
  test('denied related read does not send a request or pretend to be empty', async () => {
    const value = row(); value.permissions.view_history = false; let calls = 0;
    const ops = createOperationalSession({ related: async () => { calls += 1; } }, { state: { status: 'ready', context: context() } });
    await ops.read('history', 'events', { ticket: value }); assert.equal(calls, 0); assert.equal(ops.resource('history').status, 'denied');
  });
}
