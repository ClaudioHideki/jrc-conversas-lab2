/* global globalThis */
import test from 'node:test';
import assert from 'node:assert/strict';
import '../jrc_customers/service_desk_node_harness.mjs';
const { registerScreenExperienceCases } = await import(
  '../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/screenExperienceCases.js'
);
registerScreenExperienceCases(test, assert);
const { default: API } = await import(
  '../../app/javascript/dashboard/api/serviceDeskOperationsV2.js'
);
test('native board client sends operator filter and never rewrites it as owner', async () => {
  const previous = globalThis.axios;
  const calls = [];
  globalThis.axios = {
    get: async (url, options) => {
      calls.push({ url, options });
      return { data: { tested: true } };
    },
  };
  try {
    await API.board('1', 'tasks', {
      page: 1,
      per_page: 20,
      operator_company_id: '3',
    });
    assert.equal(calls[0].options.params.operator_company_id, '3');
    assert.equal(calls[0].options.params.owner_account_user_id, undefined);
    await API.board('1', 'incidents', {
      owner_account_user_id: '7',
      operator_company_id: '3',
    });
    assert.equal(calls[1].options.params.owner_account_user_id, '7');
    assert.throws(() => API.board('1', 'tasks', { phase: 'active' }));
  } finally {
    globalThis.axios = previous;
  }
});
