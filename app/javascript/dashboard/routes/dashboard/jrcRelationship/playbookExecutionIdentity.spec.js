import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import Panel from './PlaybookExecutionPanel.vue';
const mocks = vi.hoisted(() => ({ route: null, store: null, list: vi.fn() }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => mocks.store }));
vi.mock('dashboard/api/jrcRelationship', () => ({
  default: { playbookExecutions: mocks.list },
}));
const record = {
  id: 8,
  version: 1,
  customer_name: 'Synthetic authorized customer',
  created_at: '2026-11-06T12:00:00Z',
  snapshot: { name: 'Synthetic saved definition', results: [] },
};
const wrappers = [];
const render = props => {
  const wrapper = mount(Panel, {
    props: { allowed: true, ...props },
    global: { stubs: { RouterLink: { template: '<a><slot /></a>' } } },
  });
  wrappers.push(wrapper);
  return wrapper;
};
beforeEach(() => {
  vi.resetAllMocks();
  mocks.route = reactive({ params: { accountId: '1400' } });
  mocks.store = reactive({
    getters: {
      getCurrentUserID: 7,
      getCurrentRole: 'administrator',
      getCurrentUser: { accounts: [{ id: 1400, role: 'administrator' }] },
    },
  });
  mocks.list.mockResolvedValue({ data: { payload: [record] } });
});
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
});

it('renders the native historical projection and clears it when access is explicitly removed', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain(record.customer_name);
  await wrapper.setProps({ allowed: false });
  await flushPromises();
  expect(wrapper.text()).not.toContain(record.customer_name);
  expect(mocks.list).toHaveBeenCalledOnce();
});

it('removes the already loaded projection and requires fresh authorization after a role change', async () => {
  const wrapper = render();
  await flushPromises();
  mocks.list.mockRejectedValueOnce({
    response: { status: 403, data: { error: 'Native configure denied' } },
  });
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  expect(wrapper.text()).not.toContain(record.customer_name);
  expect(wrapper.get('[role="alert"]').text()).toContain(
    'Native configure denied'
  );
  expect(mocks.list).toHaveBeenCalledTimes(2);
});

it('aborts a pending membership response and cannot render it after the refreshed request is denied', async () => {
  let resolve;
  mocks.list.mockReturnValueOnce(
    new Promise(done => {
      resolve = done;
    })
  );
  const wrapper = render();
  await flushPromises();
  const signal = mocks.list.mock.calls[0][1].signal;
  mocks.list.mockRejectedValueOnce({
    response: { status: 403, data: { error: 'Native scope denied' } },
  });
  mocks.store.getters.getCurrentUser.accounts = [
    { id: 1400, role: 'agent', custom_role_id: 22 },
  ];
  await flushPromises();
  expect(signal.aborted).toBe(true);
  resolve({ data: { payload: [record] } });
  await flushPromises();
  expect(wrapper.text()).not.toContain(record.customer_name);
  expect(wrapper.get('[role="alert"]').text()).toContain('Native scope denied');
});

it('does not fetch without access and aborts the only owned request on unmount', async () => {
  const denied = render({ allowed: false });
  await flushPromises();
  expect(mocks.list).not.toHaveBeenCalled();
  denied.unmount();
  const wrapper = render();
  await flushPromises();
  const signal = mocks.list.mock.calls[0][1].signal;
  wrapper.unmount();
  expect(signal.aborted).toBe(true);
});
