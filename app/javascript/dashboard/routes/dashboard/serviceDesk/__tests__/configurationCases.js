// CP6 fixtures are synthetic and used exclusively by tests, never by application views.
import { configurationFields, configurationAttributes, configurationRevision, decodeConfigurationEnvelope,
  decodeConfigurationPage, confirmConfiguration } from '../helpers/configuration.js';
import { createServiceDeskConfigurationClient } from '../../../../api/serviceDeskConfigurationClient.js';
import { decodeContext } from '../helpers/contracts.js';
const unit = '10';
export const configurationContext = () => ({ account_id: '1', user_id: '7', available: true,
  units: [{ id: unit, name: 'Fixture unit', operator_company: { id: '5', name: 'Fixture operator' }, permissions: {} }],
  capabilities: { configuration: { queues: true, categories: true, priorities: true, statuses: true, services: true } } });
export const configurationRow = (resource = 'categories', overrides = {}) => ({ id: '20', account_id: '1', unit_id: unit,
  name: 'Fixture catalogue', code: 'test-catalogue', active: true, revision: 'a'.repeat(64),
  created_at: '2026-09-28T10:00:00Z', updated_at: '2026-09-28T10:00:00Z',
  ...(resource === 'queues' ? { team_id: null } : {}), ...(['priorities', 'statuses'].includes(resource) ? { position: 3 } : {}),
  ...(resource === 'statuses' ? { phase: 'open', initial: true } : {}), ...overrides });
export const configurationEnvelope = (resource = 'categories', overrides = {}) => ({ contract_version: 1, account_id: '1', resource,
  record: configurationRow(resource), ...overrides });
export const configurationReceipt = (resource = 'categories', overrides = {}) => ({ contract_version: 1, account_id: '1',
  receipt: { id: '80', account_id: '1', unit_id: unit, record_id: '20', resource, action: 'create',
    occurred_at: '2026-09-28T10:00:00Z', author_account_user_id: '15',
    after: Object.fromEntries(configurationFields(resource).map(key => [key, configurationRow(resource)[key]])), ...overrides } });
const fields = resource => Object.fromEntries(configurationFields(resource).map(key => [key, configurationRow(resource)[key]]));
const intent = (overrides = {}) => ({ action: 'create', resource: 'categories', unitId: unit, recordId: '20', auditId: '80', attributes: fields('categories'), ...overrides });
export function registerConfigurationCases(test, assert) {
  for (const resource of ['queues', 'categories', 'priorities', 'statuses', 'services']) {
    test(`CP6 closed contract ${resource}: explicit fields and preserved scope`, () => {
      assert.deepEqual(configurationAttributes(resource, fields(resource)), fields(resource));
      assert.equal(decodeConfigurationEnvelope(configurationEnvelope(resource), configurationContext(), resource, unit).unit_id, unit);
      for (const field of ['account_id', 'unit_id', 'operator_company_id', 'role', 'id']) {
        assert.throws(() => configurationAttributes(resource, { ...fields(resource), [field]: '2' }));
      }
    });
    test(`CP6 ${resource}: deactivate without deleting or replacing identity`, () => {
      const record = configurationRow(resource, { active: false });
      const result = confirmConfiguration(configurationReceipt(resource, { action: 'update', after: { ...fields(resource), active: false } }),
        configurationEnvelope(resource, { record }), intent({ resource, action: 'update', attributes: { active: false } }), configurationContext());
      assert.equal(result.active, false); assert.equal(result.id, '20');
    });
  }
  for (const resource of ['units', 'operator_companies', 'memberships', 'accounts', '__proto__']) test(`CP6 rejects unapproved resource ${resource}`, () => {
    assert.throws(() => configurationFields(resource));
  });
  test('CP6 management capability survives context decoder without using frontend admin roles', () => {
    const ctx = configurationContext();
    const raw = { ...ctx, contract_version: 1, units: [{ ...ctx.units[0], active: true, account_id: '1', operator_company: { ...ctx.units[0].operator_company, account_id: '1' } }] };
    assert.deepEqual(decodeContext(raw, { accountId: '1', userId: '7' }).capabilities.configuration, ctx.capabilities.configuration);
  });
  for (const update of [{ account_id: '2' }, { unit_id: '11' }, { revision: 'bogus' }, { active: 'true' }]) test(`CP6 rejects changed record contract ${JSON.stringify(update)}`, () => {
    assert.throws(() => decodeConfigurationEnvelope(configurationEnvelope('categories', { record: configurationRow('categories', update) }), configurationContext(), 'categories', unit));
  });
  test('CP6 membership/capability absence blocks even an apparently valid record', () => {
    const noGrant = { ...configurationContext(), units: [] };
    const noCapability = { ...configurationContext(), capabilities: { configuration: { categories: false } } };
    for (const ctx of [noGrant, noCapability]) assert.throws(() => decodeConfigurationEnvelope(configurationEnvelope(), ctx, 'categories', unit));
  });
  for (const value of ['true', 1, null]) test(`CP6 literal boolean required ${value}`, () => assert.throws(() => configurationAttributes('categories', { ...fields('categories'), active: value })));
  for (const value of [-1, 1.5, '1', 2147483648]) test(`CP6 invalid position ${value}`, () => assert.throws(() => configurationAttributes('priorities', { ...fields('priorities'), position: value })));
  test('CP6 code cannot be changed by PATCH; empty or unexpected patch denied', () => {
    for (const data of [{ code: 'different' }, {}, { destroy: true }]) assert.throws(() => configurationAttributes('categories', data, false));
  });
  test('CP6 no defaults on incomplete creation', () => assert.throws(() => configurationAttributes('categories', { name: 'Only name' })));
  test('CP6 optimistic revision is exact lowercase SHA-256', () => {
    assert.equal(configurationRevision('a'.repeat(64)), 'a'.repeat(64));
    for (const value of ['', 'A'.repeat(64), null]) assert.throws(() => configurationRevision(value));
  });
  for (const update of [{ id: '81' }, { record_id: '21' }, { account_id: '2' }, { unit_id: '11' }, { action: 'update' }, { resource: 'priorities' }, { occurred_at: null }]) test(`CP6 receipt mismatch ${JSON.stringify(update)} never confirms`, () => {
    assert.throws(() => confirmConfiguration(configurationReceipt('categories', update), configurationEnvelope(), intent(), configurationContext()));
  });
  test('CP6 acknowledgement alone cannot confirm a write', () => {
    assert.throws(() => confirmConfiguration(configurationEnvelope(), configurationEnvelope(), intent(), configurationContext()));
  });
  test('CP6 receipt and independent GET must BOTH match intended fields', () => {
    assert.throws(() => confirmConfiguration(configurationReceipt('categories', { after: { ...fields('categories'), name: 'Another value' } }), configurationEnvelope(), intent(), configurationContext()));
    assert.throws(() => confirmConfiguration(configurationReceipt(), configurationEnvelope('categories', { record: configurationRow('categories', { name: 'Changed concurrently' }) }), intent(), configurationContext()));
    assert.equal(confirmConfiguration(configurationReceipt(), configurationEnvelope(), intent(), configurationContext()).name, 'Fixture catalogue');
  });
  test('CP6 page totals are real response values, empty must actually be empty', () => {
    const payload = { contract_version: 1, account_id: '1', unit_id: unit, resource: 'categories', items: [configurationRow()], meta: { total: 1, page: 1, per_page: 20 } };
    assert.equal(decodeConfigurationPage(payload, configurationContext(), 'categories', unit, 1).meta.total, 1);
    assert.throws(() => decodeConfigurationPage({ ...payload, items: [] }, configurationContext(), 'categories', unit, 1));
    assert.equal(decodeConfigurationPage({ ...payload, items: [], meta: { total: 0, page: 1, per_page: 20 } }, configurationContext(), 'categories', unit, 1).items.length, 0);
  });
  test('CP6 client uses closed paths, idempotency header, optimistic PATCH and no delete', async () => {
    const calls = []; const http = Object.fromEntries(['get', 'post', 'patch'].map(method => [method, (...args) => { calls.push([method, ...args]); return Promise.resolve({ data: configurationEnvelope() }); }]));
    const client = createServiceDeskConfigurationClient(http);
    await client.save('1', intent(), 'same-key');
    await client.save('1', intent({ action: 'update', revision: 'a'.repeat(64), attributes: { active: false } }), 'same-key');
    await client.receipt('1', 'categories', '20', '80');
    assert.equal(calls[0][0], 'post'); assert.equal(calls[0][3].headers['Idempotency-Key'], 'same-key');
    assert.equal(calls[1][0], 'patch'); assert.equal(calls[1][2].expected_revision, 'a'.repeat(64));
    assert.equal(calls[2][1], '/api/v1/accounts/1/jrc_service_desk/configuration/categories/20/receipts/80');
    assert.equal(client.destroy, undefined);
    assert.throws(() => client.save('1', intent({ resource: 'units' }), 'key'));
    assert.throws(() => client.save('../2', intent(), 'key'));
    assert.throws(() => client.save('1', intent(), 'invalid key'));
  });
  for (const status of [401, 403, 404, 409, 422, 500]) test(`CP6 transport ${status} remains error, never success or empty`, async () => {
    const err = Object.assign(new Error('Test transport'), { response: { status } });
    const client = createServiceDeskConfigurationClient({ get: () => Promise.reject(err), post: () => Promise.reject(err) });
    await assert.rejects(() => client.list('1', 'categories', unit), e => e === err);
    await assert.rejects(() => client.save('1', intent(), 'same-key'), e => e === err);
  });
}
