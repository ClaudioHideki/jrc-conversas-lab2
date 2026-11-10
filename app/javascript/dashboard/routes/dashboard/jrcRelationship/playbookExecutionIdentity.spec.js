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
  mocks.list.mockResolvedValue({
    data: { payload: [record], meta: { per_page: 25, next_before_id: null } },
  });
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
  resolve({
    data: { payload: [record], meta: { per_page: 25, next_before_id: null } },
  });
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

it('navigates with only the last visible cursor and can return to the first page', async () => {
  mocks.list.mockResolvedValueOnce({
    data: { payload: [record], meta: { per_page: 25, next_before_id: 8 } },
  });
  const wrapper = render();
  await flushPromises();
  mocks.list.mockResolvedValueOnce({
    data: {
      payload: [{ ...record, id: 7, customer_name: 'Older visible customer' }],
      meta: { per_page: 25, next_before_id: null },
    },
  });
  await wrapper.get('[data-test="execution-next"]').trigger('click');
  await flushPromises();
  expect(mocks.list.mock.lastCall[1].params).toEqual({
    per_page: 25,
    before_id: 8,
  });
  expect(wrapper.text()).toContain('Older visible customer');
  expect(wrapper.text()).not.toContain(record.customer_name);
  await wrapper.get('[data-test="execution-previous"]').trigger('click');
  await flushPromises();
  expect(mocks.list.mock.lastCall[1].params).toEqual({ per_page: 25 });
  expect(wrapper.text()).toContain(record.customer_name);
});

it('filters using the existing selected book and resets cursor navigation when that native selection changes', async () => {
  const wrapper = render({ book: { id: 21, name: 'Selected native book' } });
  await flushPromises();
  await wrapper.get('[data-test="execution-current-book"]').setValue(true);
  await flushPromises();
  expect(mocks.list.mock.lastCall[1].params).toEqual({
    per_page: 25,
    playbook_id: 21,
  });
  await wrapper.setProps({ book: { id: 22, name: 'Other selected book' } });
  await flushPromises();
  expect(mocks.list.mock.lastCall[1].params).toEqual({
    per_page: 25,
    playbook_id: 22,
  });
  await wrapper.get('[data-test="execution-current-book"]').setValue(false);
  await flushPromises();
  expect(mocks.list.mock.lastCall[1].params).toEqual({ per_page: 25 });
});

it('retries the requested failed page without mixing in the previous page or issuing any write', async () => {
  mocks.list.mockResolvedValueOnce({
    data: { payload: [record], meta: { per_page: 25, next_before_id: 8 } },
  });
  const wrapper = render();
  await flushPromises();
  mocks.list.mockRejectedValueOnce(new Error('Synthetic read failure'));
  await wrapper.get('[data-test="execution-next"]').trigger('click');
  await flushPromises();
  expect(wrapper.text()).not.toContain(record.customer_name);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  mocks.list.mockResolvedValueOnce({
    data: {
      payload: [
        { ...record, id: 7, customer_name: 'Recovered older customer' },
      ],
      meta: { per_page: 25, next_before_id: null },
    },
  });
  await wrapper.get('[data-test="execution-reload"]').trigger('click');
  await flushPromises();
  expect(mocks.list.mock.lastCall[1].params).toEqual({
    per_page: 25,
    before_id: 8,
  });
  expect(wrapper.text()).toContain('Recovered older customer');
});

it('rejects inconsistent successful pagination metadata before showing the historical payload', async () => {
  mocks.list.mockResolvedValueOnce({
    data: { payload: [record], meta: { per_page: 25, next_before_id: 99 } },
  });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).not.toContain(record.customer_name);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(wrapper.get('[data-test="execution-next"]').element.disabled).toBe(
    true
  );
});
