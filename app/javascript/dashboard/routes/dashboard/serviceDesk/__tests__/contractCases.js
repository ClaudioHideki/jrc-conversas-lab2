// Shared assertions: Vitest wrapper and the isolated Node runner execute the
// SAME application helpers. No Vue/Rails execution is implied by the Node run.
import { canonicalId, hasServiceDeskFeature, createServiceDeskGuard, canRead, canAct, canPreviewScreen } from '../helpers/access.js';
import { ContractError, decodeContext, decodeRecord, decodeCollection, decodeTicket } from '../helpers/contracts.js';
import { normalizeQuery, QueryError, queryWithinContext, routeQuery } from '../helpers/query.js';
import { createServiceDeskSession, errorStatus } from '../helpers/session.js';
import { createServiceDeskClient } from '../../../../api/serviceDeskClient.js';
import { SERVICE_DESK_ROUTES, CORE_CATALOGS, serviceDeskRouteName } from '../routeDefinitions.js';
import { CATALOG_COLUMNS, PLANNED_SCREENS, formatTimestamp } from '../helpers/presentation.js';
import { contextPayload, identity, ticket, collection, detail, deferred, fakeClient, httpError } from './fixtures.js';
export function registerContractCases(test, assert) {
  const context = () => decodeContext(contextPayload(), identity);
  const request = () => normalizeQuery({});
  test('canonical identifiers preserve a signed bigint maximum', () => assert.equal(canonicalId('9223372036854775807'), '9223372036854775807'));
  for (const input of [null, undefined, [], {}, 0, -1, 1.5, '0', '01', '+1', '1e2', ' 1', '1/../2', '9223372036854775808', Number.MAX_SAFE_INTEGER + 1]) {
    test(`invalid identifier rejected: ${String(input)}`, () => assert.equal(canonicalId(input), null));
  }
  test('safe numeric IDs normalize without precision loss', () => assert.equal(canonicalId(10), '10'));
  for (const value of [false, undefined, null, 'true', 1]) {
    test(`feature needs literal true: ${String(value)}`, () => assert.equal(hasServiceDeskFeature({ getters: { 'accounts/isFeatureEnabledonAccount': () => value } }, '1'), false));
  }
  test('feature getter receives target account and existing key', () => {
    const calls = [];
    const store = { getters: { 'accounts/isFeatureEnabledonAccount': (...args) => { calls.push(args); return true; } } };
    assert.equal(hasServiceDeskFeature(store, '1'), true);
    assert.deepEqual(calls, [[1, 'jrc_service_desk']]);
  });
  test('guard rejects stale-store true after refresh failure', async () => {
    const guard = createServiceDeskGuard({ getters: { 'accounts/isFeatureEnabledonAccount': () => true } }, async () => { throw new Error('offline'); });
    assert.equal(await guard({ params: { accountId: '1' } }), false);
  });
  test('guard rejects a response for another account', async () => {
    const guard = createServiceDeskGuard({ getters: {} }, async () => ({ id: '2', features: { jrc_service_desk: true } }));
    assert.equal(await guard({ params: { accountId: '1' } }), false);
  });
  test('guard redirects a disabled account to native home', async () => {
    const guard = createServiceDeskGuard({ getters: {} }, async () => ({ id: '1', features: { jrc_service_desk: false } }));
    assert.deepEqual(await guard({ params: { accountId: '1' } }), { name: 'home', params: { accountId: '1' } });
  });
  test('guard allows only a matching refreshed feature', async () => {
    const guard = createServiceDeskGuard({ getters: { 'accounts/isFeatureEnabledonAccount': () => true } }, async () => ({ id: '1', features: { jrc_service_desk: true } }));
    assert.equal(await guard({ params: { accountId: '1' } }), true);
  });
  test('context preserves explicit grants without role inference', () => { const c = context(); assert.equal(canRead(c, 'tickets'), true); assert.equal(canRead(c, 'automations'), false); assert.equal(c.units[1].permissions.create_ticket, undefined); });
  for (const payload of [null, '<html>missing endpoint</html>', contextPayload({ account_id: '2' }), contextPayload({ user_id: '8' }), contextPayload({ contract_version: 2 }), contextPayload({ available: 'true' }), contextPayload({ capabilities: null })]) {
    test(`invalid context rejected: ${JSON.stringify(payload)?.slice(0, 65)}`, () => assert.throws(() => decodeContext(payload, identity), ContractError));
  }
  test('cross-account unit context rejected', () => { const p = contextPayload(); p.units[0].account_id = '2'; assert.throws(() => decodeContext(p, identity), ContractError); });
  test('cross-account operating company rejected', () => { const p = contextPayload(); p.units[0].operator_company.account_id = '2'; assert.throws(() => decodeContext(p, identity), ContractError); });
  test('inactive membership projection rejected', () => { const p = contextPayload(); p.units[0].active = false; assert.throws(() => decodeContext(p, identity), ContractError); });
  test('duplicate authorized unit rejected', () => { const p = contextPayload(); p.units.push(p.units[0]); assert.throws(() => decodeContext(p, identity), ContractError); });
  test('role string cannot grant navigation or actions', () => { const c = context(); c.role = 'administrator'; assert.equal(canPreviewScreen(c, { key: 'contracts' }), false); assert.equal(canAct({ role: 'administrator' }, 'update'), false); });
  test('structure preview is not an operational grant', () => { assert.equal(canPreviewScreen(null, { key: 'settings' }), true); assert.equal(canRead(null, 'tickets'), false); assert.equal(canAct(null, 'update'), false); });
  test('record projections discard arbitrary URLs, finance and raw snapshots', () => { const row = decodeRecord(ticket({ url: 'https://invalid.test', contract_conditions: { price: 99 }, sla_snapshot: { secret: 1 } }), context(), 'tickets'); assert.equal(row.url, undefined); assert.equal(row.contract_conditions, undefined); assert.equal(row.sla_snapshot, undefined); });
  test('text is not injected into HTML by a decoder', () => { const row = decodeRecord(ticket({ title: '<script>bad()</script>' }), context(), 'tickets'); assert.equal(row.title, '<script>bad()</script>'); });
  for (const bad of [{ account_id: '2' }, { unit_id: '99' }, { unit_id: null }, { permissions: { show: false } }, { permissions: { show: 'true' } }, { updated_at: 'not-a-date' }]) {
    test(`unsafe record rejected ${JSON.stringify(bad)}`, () => assert.throws(() => decodeRecord(ticket(bad), context(), 'tickets'), ContractError));
  }
  test('missing SLA never becomes met, zero or due today', () => { const row = decodeRecord(ticket(), context(), 'tickets'); assert.equal(row.sla, null); });
  test('authorized configuration row keeps its resource identity', () => { const row = decodeRecord({ id: '2', account_id: '1', unit_id: '10', permissions: { show: true }, name: 'Test' }, context(), 'priorities'); assert.equal(row.resource, 'priorities'); });
  test('genuine empty API collection preserves a real zero total', () => assert.deepEqual(decodeCollection(collection([]), context(), 'tickets', request()), { items: [], meta: { page: 1, per_page: 20, total: 0 } }));
  test('missing total is not replaced with list length or zero', () => assert.throws(() => decodeCollection(collection([], { meta: { page: 1, per_page: 20 } }), context(), 'tickets', request()), ContractError));
  test('collection cannot silently change requested pagination', () => assert.throws(() => decodeCollection(collection([], { meta: { page: 2, per_page: 20, total: 0 } }), context(), 'tickets', request()), ContractError));
  test('empty first page with positive total is incompatible', () => assert.throws(() => decodeCollection(collection([], { meta: { page: 1, per_page: 20, total: 2 } }), context(), 'tickets', request()), ContractError));
  test('duplicate record ids in a page are rejected', () => assert.throws(() => decodeCollection(collection([ticket(), ticket()]), context(), 'tickets', request()), ContractError));
  test('response cannot ignore selected unit', () => assert.throws(() => decodeCollection(collection(), context(), 'tickets', normalizeQuery({ unit_id: '11' })), ContractError));
  test('response cannot ignore selected operator', () => assert.throws(() => decodeCollection(collection(), context(), 'tickets', normalizeQuery({ operator_company_id: '4' })), ContractError));
  test('operator lookup constrained by selected unit is validated', () => {
    const row = { id: '3', account_id: '1', name: 'Operator', permissions: { show: true } };
    assert.equal(decodeCollection(collection([row]), context(), 'operator_companies', normalizeQuery({ unit_id: '10' })).items[0].id, '3');
    assert.throws(() => decodeCollection(collection([row]), context(), 'operator_companies', normalizeQuery({ unit_id: '11' })), ContractError);
  });
  test('detail must match requested ticket identifier', () => assert.throws(() => decodeTicket(detail(), context(), '21'), ContractError));
  test('query defaults only pagination, never operational unit', () => assert.deepEqual(normalizeQuery({}), { page: 1, per_page: 20 }));
  for (const q of [{ account_id: '2' }, { unit_id: ['10'] }, { unit_id: '10abc' }, { page: 0 }, { page: '01' }, { per_page: 101 }, { mine: 'false' }, { q: 'a'.repeat(201) }, { sort: 'id; DROP' }, { role: 'administrator' }, { source: { nested: 1 } }]) {
    test(`query rejects malformed/unknown filter ${JSON.stringify(q).slice(0, 90)}`, () => assert.throws(() => normalizeQuery(q), QueryError));
  }
  test('scope selection validates account-provided units and operators together', () => {
    assert.equal(queryWithinContext({ unit_id: '10', operator_company_id: '3' }, context()), true);
    assert.equal(queryWithinContext({ unit_id: '10', operator_company_id: '4' }, context()), false);
    assert.equal(queryWithinContext({ unit_id: '99' }, context()), false);
  });
  test('route query preserves narrowed filters', () => assert.deepEqual(routeQuery({ unit_id: '10', priority_id: '2', q: ' hello ' }), { page: 1, per_page: 20, unit_id: '10', priority_id: '2', q: 'hello' }));
  test('API adapter exposes GET-only reads, no generic mutation methods', async () => {
    const calls = [];
    const client = createServiceDeskClient({ get: async (...args) => { calls.push(args); return { data: { ok: true } }; } });
    assert.deepEqual(Object.keys(client).sort(), ['context', 'list', 'ticket']);
    await client.context('1');
    await client.list('1', 'tickets', { unit_id: '10' });
    await client.ticket('1', '20');
    assert.deepEqual(calls.map(c => c[0]), ['/api/v1/accounts/1/jrc_service_desk/ui_context', '/api/v1/accounts/1/jrc_service_desk/tickets', '/api/v1/accounts/1/jrc_service_desk/tickets/20']);
  });
  test('API adapter rejects path and filter injection before HTTP', () => {
    const client = createServiceDeskClient({ get: () => { throw new Error('must not call'); } });
    assert.throws(() => client.ticket('1', '../2'), TypeError);
    assert.throws(() => client.list('1', '../users', {}), TypeError);
    assert.throws(() => client.list('1', 'units', { mine: 'true' }), TypeError);
  });
  test('native projections require an explicit unit before any HTTP request', async () => {
    let calls = 0;
    const client = createServiceDeskClient({ get: async () => { calls += 1; return { data: {} }; } });
    for (const resource of ['assignees', 'requesters', 'teams']) {
      assert.throws(() => client.list('1', resource, {}), TypeError);
    }
    assert.equal(calls, 0);
    await client.list('1', 'assignees', { unit_id: '10' });
    assert.equal(calls, 1);
  });
  test('unknown native role does not alter client permissions', () => assert.equal(canAct({ permissions: { update: 'true' }, role: 'administrator' }, 'update'), false));
  test('disabled feature starts with no context request', async () => {
    let calls = 0;
    const s = createServiceDeskSession(fakeClient({ context: async () => { calls += 1; return contextPayload(); } }));
    await s.start({ ...identity, enabled: false });
    assert.equal(calls, 0);
    assert.equal(s.state.status, 'disabled');
    await s.load('x', 'tickets');
    assert.equal(s.resource('x').status, 'disabled');
  });
  test('confirmed context without units denies access', async () => { const s = createServiceDeskSession(fakeClient({ context: async () => contextPayload({ units: [] }) })); await s.start(identity); assert.equal(s.state.status, 'denied'); assert.equal(s.state.context, null); });
  test('flag value true as string does not enable a session', async () => { const s = createServiceDeskSession(fakeClient()); await s.start({ ...identity, enabled: 'true' }); assert.equal(s.state.status, 'disabled'); });
  test('context 404 is pending, not an empty account', async () => { const s = createServiceDeskSession(fakeClient({ context: async () => { throw httpError(404); } })); await s.start(identity); assert.equal(s.state.status, 'pending'); assert.equal(s.state.context, null); });
  test('list 404 is pending, while detail 404 is not_found', async () => {
    const s = createServiceDeskSession(fakeClient({ list: async () => { throw httpError(404); }, ticket: async () => { throw httpError(404); } }));
    await s.start(identity);
    await s.load('list', 'tickets');
    assert.equal(s.resource('list').status, 'pending');
    assert.equal(s.resource('list').meta, null);
    await s.load('detail', 'tickets', {}, '20');
    assert.equal(s.resource('detail').status, 'not_found');
  });
  test('successful nonempty and empty lists remain distinguishable', async () => {
    let empty = false;
    const s = createServiceDeskSession(fakeClient({ list: async () => empty ? collection([]) : collection() }));
    await s.start(identity);
    await s.load('list', 'tickets');
    assert.equal(s.resource('list').status, 'ready');
    empty = true;
    await s.load('list', 'tickets');
    assert.equal(s.resource('list').status, 'empty');
    assert.equal(s.resource('list').meta.total, 0);
  });
  test('failed refresh clears previously rendered rows immediately', async () => {
    const d = deferred();
    let first = true;
    const s = createServiceDeskSession(fakeClient({ list: async () => { if (first) {
        first = false;
        return collection();
      } return d.promise; } }));
    await s.start(identity);
    await s.load('list', 'tickets');
    const next = s.load('list', 'tickets');
    assert.deepEqual(s.resource('list').items, []);
    d.reject(httpError(500));
    await next;
    assert.equal(s.resource('list').status, 'error');
    assert.equal(s.resource('list').meta, null);
  });
  test('incompatible HTML response is discarded, never rendered as data', async () => { const s = createServiceDeskSession(fakeClient({ list: async () => '<html>Not Found</html>' })); await s.start(identity); await s.load('list', 'tickets'); assert.equal(s.state.status, 'invalid_contract'); assert.deepEqual(s.resource('list').items, []); });
  test('403 clears all other cached collections and record previews', async () => {
    let deny = false;
    const s = createServiceDeskSession(fakeClient({ list: async () => { if (deny)
        throw httpError(403); return collection(); } }));
    await s.start(identity);
    await s.load('good', 'tickets');
    deny = true;
    await s.load('bad', 'tickets');
    assert.equal(s.state.status, 'denied');
    assert.equal(s.state.context, null);
    assert.deepEqual(s.state.resources, {});
  });
  test('401 clears authenticated UI context', async () => { const s = createServiceDeskSession(fakeClient({ ticket: async () => { throw httpError(401); } })); await s.start(identity); await s.load('detail', 'tickets', {}, '20'); assert.equal(s.state.status, 'unauthenticated'); assert.equal(s.state.context, null); });
  test('invalid query never makes a backend request', async () => { let calls = 0; const s = createServiceDeskSession(fakeClient({ list: async () => { calls += 1; return collection(); } })); await s.start(identity); await s.load('x', 'tickets', { unit_id: '99' }); assert.equal(calls, 0); assert.equal(s.resource('x').status, 'invalid_request'); });
  test('missing capability denies read even with active unit', async () => { let calls = 0; const p = contextPayload(); delete p.capabilities.tickets; const s = createServiceDeskSession(fakeClient({ context: async () => p, list: async () => { calls += 1; return collection(); } })); await s.start(identity); await s.load('x', 'tickets'); assert.equal(calls, 0); assert.equal(s.resource('x').status, 'denied'); });
  test('late context for another Account cannot populate current session', async () => {
    const d = deferred();
    const s = createServiceDeskSession(fakeClient({ context: account => account === '1' ? d.promise : Promise.resolve(contextPayload({ account_id: '2', units: [] })) }));
    const first = s.start(identity);
    await s.start({ ...identity, accountId: '2' });
    d.resolve(contextPayload());
    await first;
    assert.equal(s.state.status, 'denied');
    assert.equal(s.state.context, null);
  });
  test('late list for previous Account is ignored', async () => {
    const d = deferred();
    const s = createServiceDeskSession(fakeClient({ list: () => d.promise }));
    await s.start(identity);
    const first = s.load('list', 'tickets');
    await s.start({ ...identity, accountId: '2', enabled: false });
    d.resolve(collection());
    await first;
    assert.equal(s.state.status, 'disabled');
    assert.deepEqual(s.state.resources, {});
  });
  test('late list for previous user is ignored', async () => {
    const d = deferred();
    const s = createServiceDeskSession(fakeClient({ list: () => d.promise }));
    await s.start(identity);
    const first = s.load('list', 'tickets');
    await s.start({ ...identity, userId: '8', enabled: false });
    d.resolve(collection());
    await first;
    assert.equal(s.state.context, null);
    assert.deepEqual(s.state.resources, {});
  });
  test('newer filter response wins over older request', async () => {
    const d = deferred();
    let n = 0;
    const s = createServiceDeskSession(fakeClient({ list: () => ++n === 1 ? d.promise : Promise.resolve(collection([])) }));
    await s.start(identity);
    const old = s.load('list', 'tickets', { q: 'old' });
    await s.load('list', 'tickets', { q: 'new' });
    d.resolve(collection());
    await old;
    assert.equal(s.resource('list').status, 'empty');
  });
  test('clearing a selected record invalidates its in-flight preview', async () => {
    const d = deferred();
    const s = createServiceDeskSession(fakeClient({ ticket: () => d.promise }));
    await s.start(identity);
    const old = s.load('p', 'tickets', {}, '20');
    s.resetResource('p');
    d.resolve(detail());
    await old;
    assert.equal(s.resource('p').status, 'idle');
    assert.equal(s.resource('p').record, null);
  });
  test('disposing session prevents late responses and deletes record state', async () => { const d = deferred(); const s = createServiceDeskSession(fakeClient({ list: () => d.promise })); await s.start(identity); const old = s.load('list', 'tickets'); s.dispose(); d.resolve(collection()); await old; assert.equal(s.state.context, null); assert.deepEqual(s.state.resources, {}); });
  test('error mappings do not interpret API absence as empty data', () => { assert.equal(errorStatus(httpError(501)), 'pending'); assert.equal(errorStatus(httpError(405)), 'pending'); assert.equal(errorStatus(httpError(500)), 'error'); assert.equal(errorStatus(new QueryError()), 'invalid_request'); });
  test('route names and paths are unique and isolated', () => {
    assert.equal(new Set(SERVICE_DESK_ROUTES.map(r => r.key)).size, SERVICE_DESK_ROUTES.length);
    assert.equal(new Set(SERVICE_DESK_ROUTES.map(r => r.path)).size, SERVICE_DESK_ROUTES.length);
    assert.ok(SERVICE_DESK_ROUTES.every(r => serviceDeskRouteName(r.key).startsWith('jrc_service_desk_')));
    assert.ok(SERVICE_DESK_ROUTES.every(r => !r.path.includes('projects') && !r.path.includes('portal') && !r.path.includes('cockpit')));
  });
  test('all core catalogs and planned routes have explicit column schemas', () => {
    CORE_CATALOGS.forEach(key => assert.ok(CATALOG_COLUMNS[key]?.length));
    SERVICE_DESK_ROUTES.filter(r => r.page === 'planned').forEach(r => assert.ok(PLANNED_SCREENS[r.key]?.columns?.length));
  });
  test('timestamps format valid values and never invent missing dates', () => { assert.equal(formatTimestamp(null, 'pt_BR'), null); assert.equal(formatTimestamp('bad', 'pt_BR'), null); assert.equal(typeof formatTimestamp('2026-09-25T10:00:00Z', 'pt_BR'), 'string'); });
}
