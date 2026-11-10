// Source-level async tests: executes the actual script-setup handlers with a
// minimal reactive harness and mocked transport. Not a Vue DOM/HTTP test.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const root = process.env.JRC_SOURCE_ROOT || path.resolve(import.meta.dirname, '..');
const file = path.join(root, 'app/javascript/dashboard/routes/dashboard/crm/views/backoffice/BackofficeRequest360.vue');
const script = readFileSync(file, 'utf8').match(/<script setup>([\s\S]*?)<\/script>/)[1]
  .replace(/^import[\s\S]*?from\s+['"][^'"]+['"];?\s*/gm, '');
const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const denial = status => ({ response: { status, data: {} } });
const make = () => {
  const route = { params: { accountId: '1', requestId: '12' }, query: {} };
  const store = { getters: { getCurrentUser: { id: 7, accounts: [] }, getCurrentRole: 'agent' } };
  const api = { show: async () => ({ data: { id: 12, title: 'Authorized refresh' } }) };
  let dispose;
  const sandbox = {
    ref: value => ({ value }), computed: getter => ({ get value() { return getter(); } }),
    watch: () => {}, onBeforeUnmount: fn => { dispose = fn; },
    useRoute: () => route, useStore: () => store, backofficeAPI: api,
    useBackofficePresentation: () => ({ text: key => key }),
  };
  vm.createContext(sandbox);
  vm.runInContext(`${script}\nglobalThis.subject = { record, historyPage, startIssue, message, error, loading, saving, action, refreshDocuments, load };`, sandbox, { timeout: 1000 });
  const state = sandbox.subject;
  state.record.value = { id: 12, title: 'Private prior customer' };
  state.historyPage.value = 3;
  state.startIssue.value = true;
  state.message.value = 'Previous success';
  return { state, api, route, dispose: () => dispose() };
};

for (const status of [401, 403, 404]) {
  test(`mutation denied with ${status} clears private data and stale interaction state`, async () => {
    const { state } = make();
    await state.action(async () => { throw denial(status); });
    assert.equal(state.record.value, null);
    assert.equal(state.startIssue.value, false);
    assert.equal(state.historyPage.value, 1);
    assert.equal(state.message.value, '');
    assert.equal(state.saving.value, false);
    assert.equal(state.error.value, 'DETAIL_ERROR');
  });
  test(`refresh denied with ${status} invalidates an older successful in-flight response`, async () => {
    const { state, api } = make();
    const older = deferred();
    api.show = () => older.promise;
    const pending = state.refreshDocuments();
    api.show = async () => { throw denial(status); };
    await state.refreshDocuments();
    assert.equal(state.record.value, null);
    older.resolve({ data: { id: 12, title: 'Stale private data' } });
    await pending;
    assert.equal(state.record.value, null);
  });
}

test('transient server failure does not discard an authorized record', async () => {
  const { state } = make();
  const original = state.record.value;
  await state.action(async () => { throw denial(500); });
  assert.equal(state.record.value, original);
  assert.equal(state.error.value, 'ACTION_ERROR');
});
test('a new successful authorized request can load data after denial', async () => {
  const { state, api } = make();
  api.show = async () => { throw denial(403); };
  await state.refreshDocuments();
  api.show = async () => ({ data: { id: 12, title: 'New authorized data' } });
  await state.load();
  assert.equal(state.record.value.title, 'New authorized data');
  assert.equal(state.error.value, '');
});
test('an old account refresh cannot overwrite current account data', async () => {
  const { state, api, route } = make();
  const old = deferred(); api.show = () => old.promise;
  const task = state.refreshDocuments();
  route.params.accountId = '2';
  state.record.value = { id: 99, title: 'Second account' };
  old.resolve({ data: { id: 12, title: 'First account' } });
  await task;
  assert.equal(state.record.value.id, 99);
});
test('unmount invalidates a pending refresh', async () => {
  const { state, api, dispose } = make();
  const old = deferred(); api.show = () => old.promise;
  const original = state.record.value;
  const task = state.refreshDocuments(); dispose();
  old.resolve({ data: { id: 12, title: 'Late result' } });
  await task;
  assert.equal(state.record.value, original);
});
test('a denial from an old account cannot clear the new account record', async () => {
  const { state, route } = make();
  const old = deferred(); const task = state.action(() => old.promise);
  route.params.accountId = '2';
  state.record.value = { id: 99, title: 'Current tenant' };
  old.reject(denial(403)); await task;
  assert.equal(state.record.value.id, 99);
});


test('a denied reload after mutation does not report a refreshed authorized success', async () => {
  const { state, api } = make();
  api.show = async () => { throw denial(403); };
  await state.action(async () => undefined);
  assert.equal(state.record.value, null);
  assert.equal(state.error.value, 'DETAIL_ERROR');
  assert.equal(state.message.value, '');
});

test('a successful explicit refresh clears a prior transient read error', async () => {
  const { state, api } = make();
  api.show = async () => { throw denial(500); };
  await state.refreshDocuments();
  assert.equal(state.error.value, 'DETAIL_ERROR');
  api.show = async () => ({ data: { id: 12, title: 'Authorized again' } });
  await state.refreshDocuments();
  assert.equal(state.record.value.title, 'Authorized again');
  assert.equal(state.error.value, '');
});
