// Test-only transports and identities; never imported by the application.
// These cases run both in the isolated Node runner and the pending Vitest suite.
import { decodeContext, decodeTicket, ContractError } from '../helpers/contracts.js';
import { decodeDashboard, decodeRelated, decodeRelatedItem, decodeAcknowledgement, verifyWrittenFields } from '../helpers/operationalContracts.js';
import { createOperationalSession } from '../helpers/operationalSession.js';
import { createServiceDeskOperationsClient } from '../../../../api/serviceDeskOperationsClient.js';
import { createTicketDraft, updateTicketDraft, newRequestKey } from '../helpers/drafts.js';
import { normalizeQuery } from '../helpers/query.js';
import { contextPayload, identity, ticket, detail, deferred, httpError } from './fixtures.js';
const context = () => decodeContext(contextPayload(), identity);
const ticketPayload = (overrides = {}) => ticket({ lock_version: 0, queue: null, team: null, assignee: null, category: null,
  permissions: { show: true, update: true, change_priority: true, view_notes: true, view_history: true, view_conversations: true, view_sla: true, assign: true, add_note: true, link_conversation: true, change_work_status: true }, ...overrides });
const record = (overrides = {}) => decodeTicket(detail(ticketPayload(overrides)), context(), '20');
const ack = (operation, overrides = {}) => ({ contract_version: 1, account_id: '1', ticket_id: '20', operation, applied: true, ...overrides });
const dashboard = () => ({ contract_version: 1, account_id: '1', dashboard: { total: 27, active: 20,
  phases: { open: 20, waiting: 0, resolved: 7, closed: 0, cancelled: 0 }, generated_at: '2026-09-25T12:00:00Z', filters: {},
  by_status: [{ id: '1', name: 'Open fixture', phase: 'open', count: 8 }, { id: '2', name: 'Working fixture', phase: 'open', count: 12 }, { id: '3', name: 'Done fixture', phase: 'resolved', count: 7 }],
  contract_conditions: { forbidden: true }, unavailable: ['csat'] } });
const row = (kind, overrides = {}) => ({ id: '5', account_id: '1', unit_id: '10', ticket_id: '20', created_at: '2026-09-25T12:00:00Z', permissions: { show: true },
  ...(kind === 'notes' ? { body: 'Real fixture note', visibility: 'internal', author: { id: '7', name: 'Test actor' } } : {}),
  ...(kind === 'conversations' ? { conversation_id: '9', conversation_display_id: '4' } : {}), ...overrides });
const collection = (kind, rows = [row(kind)], overrides = {}) => ({ contract_version: 1, account_id: '1', ticket_id: '20', kind,
  items: rows, meta: { total: rows.length, page: 1, per_page: 20 }, ...overrides });
const setup = (client = {}) => {
  const base = { state: { status: 'ready', context: context() }, dispose() { this.state.status = 'idle'; this.state.context = null; } };
  const calls = [];
  const transport = { update: async () => ack('update'), ticket: async () => detail(ticketPayload()), ...client };
  const operations = createOperationalSession(transport, base);
  return { base, operations, transport, calls };
};
const update = () => ({ ticketId: '20', ticket: { title: 'Synthetic test ticket' }, expected_lock_version: 0 });

export function registerCp4Cases(test, assert) {
  test('KPI: actual grouped payload obeys 27 = 8 + 12 + 7 and strips unknown raw data', () => {
    const result = decodeDashboard(dashboard(), context());
    assert.equal(result.total, 27); assert.equal(result.active, 20);
    assert.equal(result.by_status.reduce((n, r) => n + r.count, 0), 27);
    assert.equal(result.contract_conditions, undefined);
  });
  test('KPI: a controlled 8 -> 7 and 7 -> 8 change preserves total and reduces active', () => {
    const p = dashboard(); p.dashboard.phases.open = 19; p.dashboard.phases.resolved = 8; p.dashboard.active = 19;
    p.dashboard.by_status[0].count = 7; p.dashboard.by_status[2].count = 8;
    const d = decodeDashboard(p, context()); assert.equal(d.total, 27); assert.equal(d.active, 19);
  });
  for (const change of [
    d => { d.total = 28; }, d => { d.active = 21; }, d => { d.phases.open = -1; },
    d => { d.by_status[0].count = 9; }, d => { d.by_status[1].id = '1'; }, d => { d.total = '27'; },
    d => { d.by_status[0].phase = 'unknown'; }, d => { d.generated_at = 'invalid'; },
  ]) test(`KPI rejects inconsistent values ${change.toString()}`, () => {
    const p = dashboard(); change(p.dashboard); assert.throws(() => decodeDashboard(p, context()), ContractError);
  });
  test('KPI supports genuine empty query and never fabricates absence of fields', () => {
    const p = dashboard(); p.dashboard.total = 0; p.dashboard.active = 0; p.dashboard.by_status = [];
    Object.keys(p.dashboard.phases).forEach(k => { p.dashboard.phases[k] = 0; });
    assert.equal(decodeDashboard(p, context()).total, 0);
    delete p.dashboard.phases.closed; assert.throws(() => decodeDashboard(p, context()), ContractError);
  });
  test('KPI requires Account identity and exact filter echo', () => {
    const p = dashboard(); p.account_id = '2'; assert.throws(() => decodeDashboard(p, context()), ContractError);
    p.account_id = '1'; assert.throws(() => decodeDashboard(p, context(), { unit_id: '10' }), ContractError);
    p.dashboard.filters = { unit_id: 10, q: 'print' };
    assert.equal(decodeDashboard(p, context(), { unit_id: '10', q: ' print ', page: 2 }).total, 27);
  });
  test('acknowledgement requires operation, Account, real ticket id and applied=true', () => {
    for (const override of [{ account_id: '2' }, { operation: 'other' }, { applied: false }, { ticket_id: '01' }]) {
      assert.throws(() => decodeAcknowledgement(ack('update', override), context(), 'update', '20'), ContractError);
    }
  });
  test('notes require explicit internal visibility and matching Account, Unit, ticket and permission', () => {
    for (const override of [{ visibility: 'public' }, { account_id: '2' }, { unit_id: '99' }, { ticket_id: '21' }, { permissions: {} }]) {
      assert.throws(() => decodeRelated(collection('notes', [row('notes', override)]), context(), record(), 'notes', normalizeQuery()), ContractError);
    }
  });
  test('related item readback requires the exact created record', () => {
    const p = { ...collection('notes'), item: row('notes') };
    assert.equal(decodeRelatedItem(p, context(), record(), 'notes', '5').body, 'Real fixture note');
    assert.throws(() => decodeRelatedItem(p, context(), record(), 'notes', '6'), ContractError);
  });
  test('events only expose known real payload fields', () => {
    const event = row('events', { event_type: 'ticket_updated', author: null, data: { title: ['A', 'B'], secret: 'hidden' } });
    const result = decodeRelated(collection('events', [event]), context(), record(), 'events', normalizeQuery());
    assert.deepEqual(result.items[0].data, { title: ['A', 'B'] });
  });
  test('SLA missing calculation is unknown, never met=true', () => {
    const milestone = row('sla', { kind: 'first_response', due_at: null, achieved_at: null, met: null, calculation_pending: true, snapshot_version: 1 });
    const p = collection('sla', [milestone]);
    assert.equal(decodeRelated(p, context(), record(), 'sla', normalizeQuery()).items[0].met, null);
    milestone.met = true; assert.throws(() => decodeRelated(p, context(), record(), 'sla', normalizeQuery()), ContractError);
  });
  test('pagination refuses a success-shaped empty page before the real end', () => {
    const p = collection('notes', [], { meta: { total: 10, page: 1, per_page: 20 } });
    assert.throws(() => decodeRelated(p, context(), record(), 'notes', normalizeQuery()), ContractError);
  });
  test('draft derives initial status from the explicit permitted unit, not a hardcoded value', () => {
    const unit = { id: '10', permissions: { create_ticket: true }, initial_status: { id: '42', name: 'Configured' } };
    const draft = { unit_id: '10', title: 'Test', description: '', requester_id: '33', priority_id: '2', conversation_id: '9' };
    const result = createTicketDraft(draft, unit, 'key-1');
    assert.equal(result.ticket.status_id, '42'); assert.equal(result.conversation_id, '9');
    assert.equal(result.account_id, undefined); assert.equal(result.operator_company_id, undefined);
    assert.throws(() => createTicketDraft(draft, { ...unit, initial_status: null }, 'key-1'));
  });
  test('draft cannot select another unit or bypass a missing create grant', () => {
    const draft = { unit_id: '10', title: 'Test', description: '', requester_id: '33', priority_id: '2' };
    for (const unit of [null, { id: '11', permissions: { create_ticket: true } }, { id: '10', permissions: {} }]) {
      assert.throws(() => createTicketDraft(draft, unit, 'key'));
    }
  });
  test('request keys support secure random bytes without a randomUUID implementation', () => {
    const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'crypto');
    try {
      Object.defineProperty(globalThis, 'crypto', { configurable: true, value: { getRandomValues: bytes => { bytes.fill(7); return bytes; } } });
      assert.equal(newRequestKey(), '07'.repeat(16));
    } finally { Object.defineProperty(globalThis, 'crypto', descriptor); }
  });
  test('request keys fail safely when cryptographic randomness is absent', () => {
    const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'crypto');
    try {
      Object.defineProperty(globalThis, 'crypto', { configurable: true, value: undefined });
      assert.throws(() => newRequestKey(), TypeError);
    } finally { Object.defineProperty(globalThis, 'crypto', descriptor); }
  });
  test('edit drafts carry optimistic version and cannot change unit or requester', () => {
    const p = updateTicketDraft({ unit_id: '10', title: 'Changed', description: '', priority_id: '2', category_id: '' }, record());
    assert.equal(p.expected_lock_version, 0); assert.equal(p.ticket.category_id, null);
    assert.equal(p.ticket.unit_id, undefined); assert.equal(p.ticket.requester_id, undefined);
  });
  test('readback rejects success if persisted fields differ from requested fields', () => {
    assert.throws(() => verifyWrittenFields('update', { ticket: { title: 'Different' } }, record()), ContractError);
    assert.throws(() => verifyWrittenFields('assign', { assignment: { assignee_account_user_id: '77' } }, record()), ContractError);
    assert.throws(() => verifyWrittenFields('work_status', { status_id: '99' }, record()), ContractError);
  });

  test('API client uses exact explicit URLs, method, version and idempotency header', async () => {
    const calls = [];
    const http = Object.fromEntries(['get', 'post', 'patch'].map(method => [method, async (...args) => { calls.push([method, ...args]); return { data: { result: true } }; }]));
    const client = createServiceDeskOperationsClient(http);
    await client.create('1', { unit_id: '10', ticket: { title: 'Test' }, requestKey: 'safe-key' });
    assert.equal(calls[0][1], '/api/v1/accounts/1/jrc_service_desk/tickets');
    assert.equal(calls[0][3].headers['Idempotency-Key'], 'safe-key');
    await client.update('1', update()); assert.equal(calls[1][0], 'patch');
    await client.relatedItem('1', '20', 'notes', '5'); assert.equal(calls[2][1], '/api/v1/accounts/1/jrc_service_desk/tickets/20/notes/5');
  });
  for (const field of ['account_id', 'operator_company_id', 'unit_id', 'status_id', 'created_by_membership_id']) {
    test(`API edit rejects protected ${field} before transport`, () => {
      const client = createServiceDeskOperationsClient({ patch: () => assert.fail('must not call transport') });
      assert.throws(() => client.update('1', { ...update(), ticket: { [field]: '99' } }));
    });
  }
  for (const input of ['0', '01', '1/../../2', '1e2', [], {}, -1, '9223372036854775808']) {
    test(`API refuses manipulated route id ${String(input)}`, () => {
      const client = createServiceDeskOperationsClient({ get: () => assert.fail('must not call transport') });
      assert.throws(() => client.ticket(input, '20'));
    });
  }
  test('API does not expose arbitrary relation endpoints or unknown commands', () => {
    const client = createServiceDeskOperationsClient({ get: () => assert.fail('must not call transport') });
    assert.throws(() => client.related('1', '20', 'financials', {}));
    assert.throws(() => client.related('1', '20', 'notes', { unit_id: '10' }));
    assert.equal(client.resolve, undefined); assert.equal(client.delete, undefined);
  });

  test('write waits for persisted GET before confirming or invalidating KPIs', async () => {
    const get = deferred(), order = [];
    const { operations } = setup({ update: async () => { order.push('PATCH'); return ack('update'); },
      ticket: async () => { order.push('GET'); return get.promise; } });
    const pending = operations.write('edit', 'update', update(), record());
    await Promise.resolve(); await Promise.resolve();
    assert.deepEqual(order, ['PATCH', 'GET']); assert.equal(operations.mutation('edit').status, 'saving'); assert.equal(operations.state.revision, 0);
    get.resolve(detail(ticketPayload()));
    const saved = await pending; assert.equal(saved.id, '20'); assert.equal(operations.mutation('edit').status, 'confirmed'); assert.equal(operations.state.revision, 1);
  });
  test('2xx acknowledgement with failed readback is never reported as confirmed', async () => {
    const { operations } = setup({ ticket: async () => { throw httpError(500); } });
    assert.equal(await operations.write('edit', 'update', update(), record()), null);
    assert.equal(operations.mutation('edit').status, 'readback_pending'); assert.equal(operations.state.revision, 0);
  });
  test('a successful-looking ack followed by old persisted data is pending', async () => {
    const { operations } = setup();
    await operations.write('edit', 'update', { ...update(), ticket: { title: 'New value' } }, record());
    assert.equal(operations.mutation('edit').status, 'readback_pending');
  });
  test('server conflict keeps newer data and does not run a pretend success GET', async () => {
    const { operations } = setup({ update: async () => { throw httpError(409); }, ticket: async () => assert.fail('not after rejection') });
    await operations.write('edit', 'update', update(), record()); assert.equal(operations.mutation('edit').status, 'conflict');
  });
  for (const status of [401, 403]) test(`write revocation ${status} clears protected context`, async () => {
    const { base, operations } = setup({ update: async () => { throw httpError(status); } });
    await operations.write('edit', 'update', update(), record()); assert.equal(base.state.context, null);
    assert.equal(base.state.status, status === 401 ? 'unauthenticated' : 'denied');
  });
  test('duplicate button submission during a pending request sends one command', async () => {
    let sends = 0; const ackWait = deferred();
    const { operations } = setup({ update: () => { sends += 1; return ackWait.promise; } });
    const first = operations.write('edit', 'update', update(), record());
    assert.equal(await operations.write('edit', 'update', update(), record()), null); assert.equal(sends, 1);
    ackWait.resolve(ack('update')); await first;
  });
  test('context replacement invalidates late command/readback responses', async () => {
    const wait = deferred(); const { operations } = setup({ update: () => wait.promise });
    const pending = operations.write('edit', 'update', update(), record()); operations.clear();
    wait.resolve(ack('update')); assert.equal(await pending, null); assert.equal(operations.mutation('edit').status, 'idle');
  });
  test('unmount interruption is explicit and no late success is shown', async () => {
    const wait = deferred(); const { operations } = setup({ update: () => wait.promise });
    const pending = operations.write('edit', 'update', update(), record()); operations.cancel('edit');
    wait.resolve(ack('update')); assert.equal(await pending, null); assert.equal(operations.mutation('edit').status, 'interrupted');
  });
  test('create retry cannot change an uncertain idempotent intent', async () => {
    let sends = 0;
    const { operations } = setup({ create: async () => { sends += 1; throw httpError(500); } });
    const first = { unit_id: '10', ticket: { title: 'First' }, requestKey: 'creation-key' };
    await operations.write('create', 'create', first);
    await operations.write('create', 'create', { ...first, ticket: { title: 'Second' } });
    assert.equal(sends, 1); assert.equal(operations.mutation('create').status, 'intent_changed');
  });
  test('validation rejection permits a corrected intent because no write committed', async () => {
    let sends = 0;
    const { operations } = setup({ create: async () => { sends += 1; throw httpError(422); } });
    await operations.write('create', 'create', { unit_id: '10', ticket: { title: '' }, requestKey: 'creation-key' });
    await operations.write('create', 'create', { unit_id: '10', ticket: { title: 'Corrected' }, requestKey: 'creation-key' });
    assert.equal(sends, 2);
  });
  test('missing create unit permission denies transport even for a claimed admin UI', async () => {
    const { base, operations } = setup({ create: () => assert.fail('forbidden') });
    base.state.context.role = 'administrator';
    await operations.write('create', 'create', { unit_id: '11', ticket: {}, requestKey: 'key' });
    assert.notEqual(operations.mutation('create').status, 'confirmed');
  });
  test('note confirmation reads the actual created note, not only its parent', async () => {
    const order = [];
    const { operations } = setup({ add_note: async () => { order.push('POST'); return ack('add_note', { result_id: '5' }); },
      ticket: async () => { order.push('GET ticket'); return detail(ticketPayload()); },
      relatedItem: async () => { order.push('GET note'); return { ...collection('notes'), item: row('notes') }; } });
    await operations.write('note', 'add_note', { ticketId: '20', note: { body: 'Real fixture note' }, requestKey: 'note-key' }, record());
    assert.deepEqual(order, ['POST', 'GET ticket', 'GET note']); assert.equal(operations.mutation('note').status, 'confirmed');
  });
  test('note parent GET alone cannot prove note persistence', async () => {
    const { operations } = setup({ add_note: async () => ack('add_note', { result_id: '5' }), relatedItem: async () => { throw httpError(404); } });
    await operations.write('note', 'add_note', { ticketId: '20', note: { body: 'Real fixture note' }, requestKey: 'note-key' }, record());
    assert.notEqual(operations.mutation('note').status, 'confirmed');
  });
  test('conversation link readback must match the requested native ID', async () => {
    const { operations } = setup({ link_conversation: async () => ack('link_conversation', { result_id: '5' }),
      relatedItem: async () => ({ ...collection('conversations'), item: row('conversations', { conversation_id: '11' }) }) });
    await operations.write('link', 'link_conversation', { ticketId: '20', conversation_id: '9' }, record());
    assert.equal(operations.mutation('link').status, 'readback_pending');
  });
  test('read errors are errors and never a successful zero KPI', async () => {
    const { operations } = setup({ dashboard: async () => { throw httpError(500); } });
    await operations.read('dashboard', 'dashboard');
    assert.equal(operations.resource('dashboard').data, null); assert.equal(operations.resource('dashboard').status, 'error');
  });
  test('dashboard response from another Account invalidates context', async () => {
    const { base, operations } = setup({ dashboard: async () => ({ ...dashboard(), account_id: '2' }) });
    await operations.read('dashboard', 'dashboard'); assert.equal(base.state.context, null); assert.equal(base.state.status, 'invalid_contract');
  });
  test('late dashboard response cannot overwrite a newer filtered request', async () => {
    const first = deferred(); let calls = 0;
    const { operations } = setup({ dashboard: () => (++calls === 1 ? first.promise : Promise.resolve(dashboard())) });
    const pending = operations.read('kpi', 'dashboard'); await operations.read('kpi', 'dashboard');
    const late = dashboard(); late.dashboard.total = 999; first.resolve(late); await pending;
    assert.equal(operations.resource('kpi').data.total, 27);
  });
}
