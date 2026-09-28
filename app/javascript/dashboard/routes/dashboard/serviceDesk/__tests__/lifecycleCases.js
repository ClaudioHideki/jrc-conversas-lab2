// Test-only fixtures and transports. No application imports this module.
import { decodeContext, decodeTicket } from '../helpers/contracts.js';
import { decodeLifecycle, decodeLifecycleTransition, decodeConfiguration, decodeConfigurationList, verifyLifecycleIntent, sameLifecycleDefinition, createLifecycleSession } from '../helpers/lifecycle.js';
import { createServiceDeskLifecycleClient } from '../../../../api/serviceDeskLifecycleClient.js';
import { contextPayload, identity, ticket, detail, deferred, httpError } from './fixtures.js';
export const lcContext = () => decodeContext(contextPayload(), identity);
export const lcTicket = () => decodeTicket(detail(ticket({ lock_version: 0 })), lcContext(), '20');
export const lcTransition = (override = {}) => ({ id: '80', account_id: '1', unit_id: '10', ticket_id: '20', policy_version_id: '40', policy_version: 1,
  action: 'resolve', rule_key: 'resolve', request_key: 'intent-1', from_status_id: '1', to_status_id: '2',
  occurred_at: '2026-09-28T12:00:00Z', author: { account_user_id: '70', name: 'Fixture operator' },
  payload: { note: 'Resolution note', solution: 'Actual fixture fix', fields: { accepted: true }, evidence_note_ids: [7], sla: { cycle_id: null } }, ...override });
export const lcPayload = (override = {}) => ({ contract_version: 1, account_id: '1', unit_id: '10', ticket_id: '20', lock_version: 0, service_id: null,
  policy: { id: '40', version: 1, digest: 'a'.repeat(64), pinned: true }, unavailable_reason: null, pause: null, cycle: null, reopening: null,
  options: [{ key: 'resolve', action: 'resolve', to_status_id: '2', to_status_name: 'Resolved fixture',
    requirements: { note: true, solution: true, evidence: true, classification: false, fields: { accepted: { label: 'Fixture accepted', type: 'boolean', required: true, equals: true } } }, reasons: [] }],
  history: [], meta: { page: 1, per_page: 20, total: 0 }, ...override });
const command = () => ({ rule_key: 'resolve', expected_lock_version: 0, expected_policy_version_id: '40', note: 'Resolution note', solution: 'Actual fixture fix', evidence_note_ids: ['7'], fields: { accepted: true } });
const acknowledgement = () => ({ contract_version: 1, account_id: '1', applied: true, operation: 'lifecycle', ticket_id: '20', result_id: '80' });
const persistedTicket = () => detail(ticket({ lock_version: 1, status: { id: '2', name: 'Resolved fixture' } }));
function setup(overrides = {}) {
  let ctx = lcContext(); const calls = []; let reads = 0;
  const client = { read: async () => { calls.push('GET lifecycle'); reads += 1; return reads === 1 ? lcPayload() : lcPayload({ lock_version: 1, options: [], history: [lcTransition()], meta: { page: 1, per_page: 20, total: 1 } }); },
    apply: async () => { calls.push('POST'); return acknowledgement(); }, transition: async () => { calls.push('GET transition'); return { contract_version: 1, account_id: '1', transition: lcTransition() }; },
    ticket: async () => { calls.push('GET ticket'); return persistedTicket(); }, ...overrides };
  const session = createLifecycleSession(client, () => ctx);
  return { session, client, calls, replaceContext: value => { ctx = value; } };
}
export function registerLifecycleCases(test, assert) {
  test('valid lifecycle data includes only explicit capabilities and version', () => {
    const data = decodeLifecycle(lcPayload(), lcContext(), lcTicket());
    assert.equal(data.policy.id, '40'); assert.equal(data.options[0].key, 'resolve'); assert.equal(data.cycle, null);
    assert.equal(data.options[0].requirements.fields.accepted.equals, true);
  });
  for (const [label, mutate] of [
    ['another account', p => { p.account_id = '2'; }], ['another unit', p => { p.unit_id = '11'; }],
    ['another ticket', p => { p.ticket_id = '21'; }], ['fake version', p => { p.contract_version = 2; }],
    ['options without policy', p => { p.policy = null; }], ['unknown action', p => { p.options[0].action = 'grant_admin'; }],
    ['bad digest', p => { p.policy.digest = 'fake'; }], ['duplicate option', p => { p.options.push(p.options[0]); }],
    ['unknown clock', p => { p.options[0].reasons = [{ code: 'x', name: 'x', clocks: ['hidden'] }]; }],
    ['negative total', p => { p.meta.total = -1; }], ['zero page', p => { p.meta.page = 0; }],
    ['history without count', p => { p.history = [lcTransition()]; }], ['wrong evidence type', p => { p.options[0].requirements.evidence = 'yes'; }],
    ['unsafe field key', p => { p.options[0].requirements.fields = JSON.parse('{"__proto__":{"label":"x","type":"text","required":false}}'); }],
  ]) test(`rejects ${label}`, () => { const p = lcPayload(); mutate(p); assert.throws(() => decodeLifecycle(p, lcContext(), lcTicket())); });
  test('missing policy is unavailable, not a default enabled operation', () => {
    const data = decodeLifecycle(lcPayload({ policy: null, options: [], unavailable_reason: 'no_applicable_policy' }), lcContext(), lcTicket());
    assert.equal(data.options.length, 0); assert.equal(data.unavailable_reason, 'no_applicable_policy');
  });
  test('admin label cannot grant a missing unit', () => { const ctx = lcContext(); ctx.units = []; ctx.role = 'administrator'; assert.throws(() => decodeLifecycle(lcPayload(), ctx, lcTicket())); });
  test('no feature/context means no read or write network call', async () => {
    const obj = setup(); obj.replaceContext({ ...lcContext(), available: false });
    await obj.session.load(lcTicket()); await obj.session.apply(lcTicket(), command(), 'intent-1');
    assert.equal(obj.calls.length, 0); assert.notEqual(obj.session.state.writeStatus, 'confirmed');
  });
  test('business transition requires POST then independent transition, ticket and lifecycle reads', async () => {
    const obj = setup(); await obj.session.load(lcTicket()); const result = await obj.session.apply(lcTicket(), command(), 'intent-1');
    assert.equal(result.status.id, '2'); assert.equal(obj.session.state.writeStatus, 'confirmed');
    assert.deepEqual(obj.calls, ['GET lifecycle', 'POST', 'GET transition', 'GET ticket', 'GET lifecycle']);
  });
  test('write ACK alone never confirms persistence', async () => {
    const pending = deferred(); const obj = setup({ ticket: () => pending.promise });
    await obj.session.load(lcTicket()); const work = obj.session.apply(lcTicket(), command(), 'intent-1');
    await new Promise(resolve => setTimeout(resolve, 0)); assert.equal(obj.session.state.writeStatus, 'saving');
    pending.resolve(persistedTicket()); await work; assert.equal(obj.session.state.writeStatus, 'confirmed');
  });
  test('duplicate submit while saving is ignored without a second mutation', async () => {
    const pending = deferred(); let count = 0; const obj = setup({ apply: () => { count += 1; return pending.promise; } });
    await obj.session.load(lcTicket()); const first = obj.session.apply(lcTicket(), command(), 'intent-1');
    assert.equal(await obj.session.apply(lcTicket(), command(), 'intent-1'), null); assert.equal(count, 1);
    pending.resolve(acknowledgement()); await first;
  });
  for (const [label, stage, mutation] of [
    ['ack not applied', 'apply', () => ({ ...acknowledgement(), applied: false })],
    ['foreign ack', 'apply', () => ({ ...acknowledgement(), account_id: '2' })],
    ['different transition key', 'transition', () => ({ contract_version: 1, account_id: '1', transition: lcTransition({ request_key: 'different' }) })],
    ['wrong policy version', 'transition', () => ({ contract_version: 1, account_id: '1', transition: lcTransition({ policy_version_id: '41' }) })],
    ['wrong persisted note', 'transition', () => ({ contract_version: 1, account_id: '1', transition: lcTransition({ payload: { ...lcTransition().payload, note: 'Different' } }) })],
    ['wrong persisted evidence', 'transition', () => ({ contract_version: 1, account_id: '1', transition: lcTransition({ payload: { ...lcTransition().payload, evidence_note_ids: [8] } }) })],
    ['old ticket status', 'ticket', () => detail(ticket({ lock_version: 0 }))],
    ['foreign persisted ticket', 'ticket', () => detail(ticket({ account_id: '2' }))],
  ]) test(`readback rejects ${label}`, async () => {
    const obj = setup({ [stage]: async () => mutation() }); await obj.session.load(lcTicket());
    assert.equal(await obj.session.apply(lcTicket(), command(), 'intent-1'), null);
    assert.notEqual(obj.session.state.writeStatus, 'confirmed');
  });
  test('all user-supplied lifecycle fields must match the persisted transition', () => {
    const row = decodeLifecycleTransition(lcTransition(), lcContext(), lcTicket());
    assert.equal(verifyLifecycleIntent(row, command()), true);
    for (const changed of [{ solution: 'Other' }, { fields: { accepted: false } }, { reason_code: 'secret' }, { evidence_note_ids: [] }])
      assert.throws(() => verifyLifecycleIntent(row, { ...command(), ...changed }));
  });
  test('uncertain outcome can retry exactly the same key/payload without creating a new intent', async () => {
    let calls = 0; const sent = [];
    const obj = setup({ apply: async (_a, _t, cmd, key) => { sent.push([cmd, key]); return acknowledgement(); },
      ticket: async () => { if (++calls === 1) throw new Error('Readback failed'); return persistedTicket(); } });
    await obj.session.load(lcTicket()); await obj.session.apply(lcTicket(), command(), 'intent-1');
    assert.equal(obj.session.state.writeStatus, 'readback_pending');
    await obj.session.load(lcTicket());
    assert.equal((await obj.session.apply(lcTicket(), command(), 'intent-1')).status.id, '2');
    assert.deepEqual(sent[0], sent[1]);
  });
  test('uncertain attempt cannot silently switch to a changed intent', async () => {
    let sent = 0; const obj = setup({ apply: async () => { sent += 1; throw new Error('Unknown write result'); } });
    await obj.session.load(lcTicket()); await obj.session.apply(lcTicket(), command(), 'intent-1');
    await obj.session.apply(lcTicket(), { ...command(), note: 'Changed' }, 'intent-2');
    assert.equal(sent, 1); assert.notEqual(obj.session.state.writeStatus, 'confirmed');
  });
  for (const [status, code, expected] of [[403,'forbidden','denied'],[401,'unauthorized','denied'],[409,'conflict','conflict'],[422,'invalid_input','invalid_input'],[422,'lifecycle_dependency','dependency']])
    test(`backend ${status}/${code} has no fake success`, async () => { const obj = setup({ apply: async () => { throw { response: { status, data: { code } } }; } }); await obj.session.load(lcTicket()); await obj.session.apply(lcTicket(), command(), 'intent-1'); assert.equal(obj.session.state.writeStatus, expected); });
  test('account change cancels stale response and clears prior identity data', async () => {
    const pending = deferred(); const obj = setup({ read: () => pending.promise }); const load = obj.session.load(lcTicket());
    obj.replaceContext({ ...lcContext(), account_id: '2' }); obj.session.clear(); pending.resolve(lcPayload()); await load;
    assert.equal(obj.session.state.data, null); assert.equal(obj.session.state.writeStatus, 'idle');
  });
  test('older read cannot overwrite a newer read', async () => {
    const first = deferred(); let count = 0;
    const obj = setup({ read: () => ++count === 1 ? first.promise : Promise.resolve(lcPayload({ lock_version: 2 })) });
    const old = obj.session.load(lcTicket()); await obj.session.load(lcTicket()); first.resolve(lcPayload()); await old;
    assert.equal(obj.session.state.data.lock_version, 2);
  });
  test('the client uses scoped routes and rejects caller-selected Account and author in mutation body', async () => {
    const calls = []; const client = createServiceDeskLifecycleClient({ post: async (...args) => { calls.push(args); return { data: acknowledgement() }; } });
    await client.apply('1','20',command(),'intent-1'); assert.equal(calls[0][0], '/api/v1/accounts/1/jrc_service_desk/tickets/20/lifecycle');
    assert.equal(calls[0][2].headers['Idempotency-Key'], 'intent-1');
    for (const key of ['account_id','unit_id','operator_company_id','actor_membership_id','status_id']) assert.throws(() => client.apply('1','20',{ ...command(), [key]: '99' },'intent-1'));
    for (const bad of ['../2','01','0','1?unit_id=2']) assert.throws(() => client.apply(bad,'20',command(),'intent-1'));
  });
  test('publishing requires matching unit and compares exact canonical JSON instead of object key order', () => {
    const row = { id:'1', account_id:'1', unit_id:'10', name:'Policy', service_id:null, enabled:true, version_id:'40', version:1,digest:'a'.repeat(64),definition:{a:1,b:{c:true}} };
    assert.equal(decodeConfiguration(row,lcContext(),'10','policies').version,1);
    assert.throws(() => decodeConfiguration(row,lcContext(),'11','policies'));
    assert.equal(sameLifecycleDefinition(row.definition,{b:{c:true},a:1}),true);
    assert.equal(sameLifecycleDefinition(row.definition,{b:{c:false},a:1}),false);
    assert.throws(() => decodeConfigurationList({contract_version:1,account_id:'1',unit_id:'10',items:[row],meta:{page:1,per_page:20,total:0}},lcContext(),'10','policies'));
  });
}
