// Explicit synthetic fixtures for tests; no view imports this file.
import { structureContext, structureAttributes, structureRecord, structurePage, confirmStructure, createStructureAccess } from '../helpers/structure.js';
import { createServiceDeskStructureClient } from '../../../../api/serviceDeskStructureClient.js';
const context = () => ({ account_id: '1', user_id: '10', account_user_id: '15', available: true, capabilities: { operator_companies: true, units: true, unit_memberships: true } });
const contextEnvelope = () => ({ ...context(), contract_version: 1 });
const row = (resource = 'units') => ({ id: '5', account_id: '1', name: 'Test unit', code: 'test-unit', active: true, operator_company_id: '2',
  unit_id: '5', account_user_id: '25', revision: 'a'.repeat(64), created_at: '2026-09-28T10:00:00Z', updated_at: '2026-09-28T10:00:00Z' });
const envelope = (resource = 'units') => ({ contract_version: 1, account_id: '1', resource, record: row(resource), audit_id: '60' });
const intent = () => ({ resource: 'units', action: 'create', reason: 'CHG-1', attributes: { name: 'Test unit', code: 'test-unit', active: true, operator_company_id: '2' } });
const receipt = () => ({ contract_version: 1, account_id: '1', receipt: { namespace: 'jrc_service_desk_structure_v1', id: '60', action: 'create', account_id: 1,
  resource: 'units', record_id: 5, author_user_id: 10, author_account_user_id: 15, fingerprint: 'a'.repeat(64), reason: 'CHG-1',
  occurred_at: '2026-09-28T10:00:00Z', before: null, after: { ...row(), id: 5, account_id: 1, operator_company_id: 2 } } });

export function registerStructureCases(test, assert) {
  test('D01 structural context has no operational assumptions', () => {
    const value = structureContext(contextEnvelope(), { accountId: 1, userId: 10 });
    assert.equal(value.account_user_id, '15'); assert.equal(value.units, undefined);
    assert.equal(value.tickets, undefined); assert.equal(value.capabilities.tickets_view, undefined);
  });
  for (const change of [{ account_id: '2' }, { user_id: '11' }, { available: false }, { account_user_id: null }, { capabilities: { units: true } }]) {
    test(`D01 rejects context mismatch ${JSON.stringify(change)}`, () => assert.throws(() => structureContext({ ...contextEnvelope(), ...change }, { accountId: 1, userId: 10 })));
  }
  for (const resource of ['operator_companies', 'units', 'unit_memberships']) {
    test(`D01 ${resource}: no authority/ownership injection`, () => {
      const fields = resource === 'unit_memberships' ? { unit_id: '5', account_user_id: '25', active: true } : { name: 'Real', code: 'real', active: true, ...(resource === 'units' ? { operator_company_id: '2' } : {}) };
      assert.deepEqual(structureAttributes(resource, fields, true), fields);
      for (const key of ['id', 'account_id', 'role', 'permissions', 'authority', 'is_admin']) assert.throws(() => structureAttributes(resource, { ...fields, [key]: '2' }, true));
      assert.throws(() => structureAttributes(resource, { ...fields, active: 'true' }, true));
      assert.throws(() => structureAttributes(resource, {}, true));
      assert.deepEqual(structureAttributes(resource, { active: false }, false), { active: false });
    });
  }
  test('D01 revision and Account are checked in every row', () => {
    assert.equal(structureRecord(envelope(), context(), 'units').id, '5');
    for (const changes of [{ account_id: '2' }, { revision: 'bad' }, { id: '../5' }, { active: 1 }]) {
      assert.throws(() => structureRecord({ ...envelope(), record: { ...row(), ...changes } }, context(), 'units'));
    }
  });
  test('D01 a POST response alone does not confirm persistence', () => {
    assert.throws(() => confirmStructure(envelope(), envelope(), envelope(), context(), intent()));
    assert.equal(confirmStructure(envelope(), receipt(), envelope(), context(), intent()).name, 'Test unit');
  });
  for (const changes of [{ id: '61' }, { record_id: 6 }, { account_id: 2 }, { author_user_id: 20 }, { author_account_user_id: 30 }, { action: 'update' }, { resource: 'units2' }, { namespace: 'wrong' }, { fingerprint: 'invalid' }, { before: {} }, { occurred_at: null }]) {
    test(`D01 audit proof mismatch ${JSON.stringify(changes)}`, () => assert.throws(() => confirmStructure(envelope(), { ...receipt(), receipt: { ...receipt().receipt, ...changes } }, envelope(), context(), intent())));
  }
  test('D01 current record and audited fields must both match the submitted values', () => {
    assert.throws(() => confirmStructure(envelope(), receipt(), { ...envelope(), record: { ...row(), name: 'Changed by another person' } }, context(), intent()));
    assert.throws(() => confirmStructure(envelope(), { ...receipt(), receipt: { ...receipt().receipt, after: { ...row(), name: 'Wrong audit' } } }, envelope(), context(), intent()));
    assert.throws(() => confirmStructure(envelope(), receipt(), envelope(), { ...context(), capabilities: { units: false } }, intent()));
  });
  test('D01 pagination distinguishes confirmed empty data from inconsistent payloads', () => {
    const payload = { ...envelope(), items: [row()], meta: { total: 1, page: 1, per_page: 25 } };
    assert.equal(structurePage(payload, context(), 'units', 1).meta.total, 1);
    assert.throws(() => structurePage({ ...payload, items: [] }, context(), 'units', 1));
    assert.equal(structurePage({ ...payload, items: [], meta: { total: 0, page: 1, per_page: 25 } }, context(), 'units', 1).items.length, 0);
  });
  test('D01 client uses only explicit structural endpoints and request keys', async () => {
    const calls = []; const transport = Object.fromEntries(['get','post','patch'].map(method => [method, (...args) => { calls.push([method,...args]); return Promise.resolve({ data: envelope() }); }]));
    const api = createServiceDeskStructureClient(transport);
    await api.context('1'); await api.save('1', intent(), 'manual-key');
    await api.save('1', { ...intent(), action: 'update', recordId: '5', revision: 'a'.repeat(64), attributes: { active: false } }, 'manual-update');
    assert.equal(calls[1][0], 'post'); assert.equal(calls[1][3].headers['Idempotency-Key'], 'manual-key');
    assert.equal(calls[2][0], 'patch'); assert.equal(calls[2][2].expected_revision, 'a'.repeat(64));
    assert.equal(api.destroy, undefined); assert.equal(api.initialize, undefined);
    assert.throws(() => api.save('1', { ...intent(), resource: 'tickets' }, 'x'));
    assert.throws(() => api.save('../2', intent(), 'x'));
  });
  for (const code of [401,403,404,409,422,500]) test(`D01 transport ${code} never confirms success`, async () => {
    const error = Object.assign(new Error('synthetic transport'), { response: { status: code } });
    const api = createServiceDeskStructureClient({ get: () => Promise.reject(error), post: () => Promise.reject(error) });
    await assert.rejects(() => api.list('1','units'), e => e === error);
    await assert.rejects(() => api.save('1',intent(),'same-key'), e => e === error);
  });
  test('D01 flag false issues no structural request', async () => {
    let calls = 0; const access = createStructureAccess({ context: () => { calls += 1; return contextEnvelope(); } });
    await access.refresh({ accountId: 1, userId: 10, enabled: false });
    assert.equal(calls, 0); assert.equal(access.state.visible, false);
  });
  test('D01 stale responses cannot restore context after Account change', async () => {
    let resolve; const access = createStructureAccess({ context: () => new Promise(done => { resolve = done; }) });
    const pending = access.refresh({ accountId: 1, userId: 10, enabled: true });
    await access.refresh({ accountId: 2, userId: 10, enabled: false }); resolve(contextEnvelope()); await pending;
    assert.equal(access.state.visible, false); assert.equal(access.state.context, null);
  });
  test('D01 capability revocation clears the structural context', async () => {
    let deny = false;
    const access = createStructureAccess({ context: async () => { if (deny) throw Object.assign(new Error(), { response: { status: 403 } }); return contextEnvelope(); } });
    await access.refresh({ accountId: 1, userId: 10, enabled: true }); assert.equal(access.state.visible, true);
    deny = true; await access.refresh({ accountId: 1, userId: 10, enabled: true });
    assert.equal(access.state.visible, false); assert.equal(access.state.context, null);
  });
  test('D01 routine revalidation preserves only the same confirmed authority object', async () => {
    const access = createStructureAccess({ context: async () => contextEnvelope() });
    const identity = { accountId: 1, userId: 10, enabled: true };
    await access.refresh(identity); const original = access.state.context;
    await access.refresh(identity); assert.equal(access.state.context, original);
  });
  test('D01 a changed action grant replaces context so the view clears drafts', async () => {
    let limited = false;
    const access = createStructureAccess({ context: async () => ({ ...contextEnvelope(), capabilities: { ...context().capabilities, units: !limited } }) });
    const identity = { accountId: 1, userId: 10, enabled: true };
    await access.refresh(identity); const original = access.state.context;
    limited = true; await access.refresh(identity);
    assert.notEqual(access.state.context, original); assert.equal(access.state.context.capabilities.units, false);
  });

}
