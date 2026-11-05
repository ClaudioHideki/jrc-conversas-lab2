import { flushPromises, shallowMount, RouterLinkStub } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, expect, it, vi } from 'vitest';
import Mirror from './BackofficeApprovalMirror.vue';
import RequestDetail from 'dashboard/routes/dashboard/approvals/RequestDetail.vue';

const mocks = vi.hoisted(() => ({
  get: vi.fn(),
  client: vi.fn(),
  route: null,
  getters: null,
}));
vi.mock('dashboard/api/approvals', () => ({ approvalClient: mocks.client }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
const record = { id: 5, order: { id: 6 }, contract: { id: 7 } };
const row = {
  id: 12,
  state: 'pending',
  policy_name: 'Synthetic rule',
  policy_version: 1,
  resource_type: 'JrcCrm::BackofficeRequest',
  resource_id: 5,
  issuer_company_id: 2,
  business_unit_id: 3,
};
const result = (data, total = 1) => ({
  data,
  headers: { 'x-total-count': String(total) },
});
const render = () =>
  shallowMount(Mirror, {
    props: { record },
    global: { stubs: { RouterLink: RouterLinkStub } },
  });
const button = (wrapper, text) =>
  wrapper.findAll('button').find(item => item.text() === text);
beforeEach(() => {
  mocks.route = reactive({ params: { accountId: '1' } });
  mocks.getters = reactive({
    getCurrentUserID: 9,
    getCurrentRole: 'administrator',
    getCurrentUser: { accounts: [] },
    'accounts/isFeatureEnabledonAccount': () => true,
  });
  mocks.client.mockReturnValue({ get: mocks.get });
  mocks.get.mockImplementation(path =>
    Promise.resolve(
      {
        context: {
          data: {
            account_id: 1,
            member_id: 9,
            scopes: [
              {
                issuer_company_id: 2,
                business_unit_id: 3,
                capabilities: ['view_audit'],
              },
            ],
          },
        },
        requests: result([row]),
      }[path] || { data: row }
    )
  );
});
it('uses explicit native origin filters and shows the reused detail read-only with scoped audit access', async () => {
  const wrapper = render();
  await flushPromises();
  expect(mocks.client).toHaveBeenCalledWith('1');
  expect(mocks.get).toHaveBeenCalledWith('requests', {
    resource_type: 'JrcCrm::BackofficeRequest',
    resource_id: 5,
    page: 1,
    per_page: 10,
  });
  await wrapper.get('.grid button').trigger('click');
  await flushPromises();
  expect(wrapper.getComponent(RequestDetail).props()).toMatchObject({
    request: row,
    readOnly: true,
    auditAllowed: true,
  });
  expect(wrapper.getComponent(RouterLinkStub).props('to')).toEqual({
    name: 'jrc_approvals',
    params: { accountId: '1', screen: 'inbox', id: 12 },
  });
  wrapper.unmount();
});
it('does not expose report access from another company or unit capability', async () => {
  mocks.get.mockImplementation(path =>
    Promise.resolve(
      {
        context: {
          data: {
            account_id: 1,
            member_id: 9,
            scopes: [
              {
                issuer_company_id: 2,
                business_unit_id: 99,
                capabilities: ['view_audit'],
              },
            ],
          },
        },
        requests: result([row]),
      }[path] || { data: row }
    )
  );
  const wrapper = render();
  await flushPromises();
  await wrapper.get('.grid button').trigger('click');
  await flushPromises();
  expect(wrapper.getComponent(RequestDetail).props('auditAllowed')).toBe(false);
  wrapper.unmount();
});
it('pages through native results and resets to the first page on order and contract selection', async () => {
  mocks.get.mockImplementation(path =>
    Promise.resolve(
      path === 'context' ? { data: { scopes: [] } } : result([row], 12)
    )
  );
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'Next').trigger('click');
  await flushPromises();
  expect(mocks.get).toHaveBeenLastCalledWith(
    'requests',
    expect.objectContaining({ page: 2 })
  );
  await button(wrapper, 'Origin order').trigger('click');
  await flushPromises();
  expect(mocks.get).toHaveBeenLastCalledWith(
    'requests',
    expect.objectContaining({
      resource_type: 'JrcCrm::SalesOrder',
      resource_id: 6,
      page: 1,
    })
  );
  await button(wrapper, 'Linked contract').trigger('click');
  await flushPromises();
  expect(mocks.get).toHaveBeenLastCalledWith(
    'requests',
    expect.objectContaining({
      resource_type: 'JrcCrm::Contract',
      resource_id: 7,
      page: 1,
    })
  );
  wrapper.unmount();
});
it('clears the prior detail when a refreshed native request is denied', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.get('.grid button').trigger('click');
  await flushPromises();
  mocks.get.mockRejectedValue({ response: { status: 403 } });
  await button(wrapper, 'Refresh').trigger('click');
  await flushPromises();
  expect(wrapper.findComponent(RequestDetail).exists()).toBe(false);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  wrapper.unmount();
});
it('rejects a detail that does not belong to the selected native origin', async () => {
  const wrapper = render();
  await flushPromises();
  mocks.get.mockResolvedValue({ data: { ...row, resource_id: 99 } });
  await wrapper.get('.grid button').trigger('click');
  await flushPromises();
  expect(wrapper.findComponent(RequestDetail).exists()).toBe(false);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  wrapper.unmount();
});
it('discards an old detail response after switching accounts', async () => {
  const wrapper = render();
  await flushPromises();
  let finish;
  mocks.get.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await wrapper.get('.grid button').trigger('click');
  mocks.route.params.accountId = '2';
  await flushPromises();
  finish({ data: row });
  await flushPromises();
  expect(wrapper.findComponent(RequestDetail).exists()).toBe(false);
  expect(mocks.client).toHaveBeenCalledWith('2');
  wrapper.unmount();
});
it('clears context and rows when native account membership changes', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.get('.grid button').trigger('click');
  await flushPromises();
  mocks.get.mockRejectedValue({ response: { status: 403 } });
  mocks.getters.getCurrentUser.accounts = [{ id: 1, permissions: [] }];
  await flushPromises();
  expect(wrapper.findComponent(RequestDetail).exists()).toBe(false);
  expect(wrapper.findAll('.grid button')).toHaveLength(0);
  wrapper.unmount();
});
it('does not query a feature-disabled account', async () => {
  mocks.getters['accounts/isFeatureEnabledonAccount'] = () => false;
  const wrapper = render();
  await flushPromises();
  expect(mocks.get).not.toHaveBeenCalled();
  expect(wrapper.find('[role="status"]').exists()).toBe(true);
  wrapper.unmount();
});
it('discards a pending detail on unmount', async () => {
  const wrapper = render();
  await flushPromises();
  let finish;
  mocks.get.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await wrapper.get('.grid button').trigger('click');
  wrapper.unmount();
  finish({ data: row });
  await flushPromises();
  expect(wrapper.emitted('decide')).toBeUndefined();
});
