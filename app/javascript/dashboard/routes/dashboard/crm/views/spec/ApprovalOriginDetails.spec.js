import { shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, expect, it, vi } from 'vitest';
import Contracts from '../contracts/ContractsView.vue';
import Orders from '../orders/SalesOrdersView.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  router: { replace: vi.fn() },
  alert: vi.fn(),
  contracts: { list: vi.fn(), show: vi.fn(), history: vi.fn() },
  orders: { list: vi.fn(), show: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => mocks.router,
}));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));
vi.mock('dashboard/api/crm/commercialCycle', () => ({
  contractsAPI: mocks.contracts,
  salesOrdersAPI: mocks.orders,
}));
vi.mock('dashboard/routes/dashboard/approvals/ApprovalGateBadge.vue', () => ({
  default: { template: '<span />' },
}));
const record = (id, code) => ({
  id,
  code,
  contract_number: code,
  order_number: code,
  status: 'draft',
  signature_status: 'draft',
  total_cents: 1000,
  monthly_cents: 1000,
  items: [],
  documents: [],
  attachments: [],
  history: [],
});
const mountPage = Component =>
  shallowMount(Component, {
    global: { stubs: { Teleport: true }, directives: { tooltip: () => {} } },
  });
beforeEach(() => {
  mocks.route = reactive({ params: { accountId: '17' }, query: {} });
  mocks.router.replace.mockReset().mockResolvedValue();
  mocks.alert.mockReset();
  mocks.contracts.list.mockReset().mockResolvedValue({ data: [] });
  mocks.contracts.show
    .mockReset()
    .mockResolvedValue({ data: record(99, 'SYNTHETIC-CONTRACT-99') });
  mocks.contracts.history.mockReset().mockResolvedValue({ data: [] });
  mocks.orders.list.mockReset().mockResolvedValue({ data: [] });
  mocks.orders.show
    .mockReset()
    .mockResolvedValue({ data: record(99, 'SYNTHETIC-ORDER-99') });
});
it('opens an authorized contract by exact URL ID even when it is outside the filtered list', async () => {
  mocks.route.query = { contractId: '99', customer_segment_id: '8' };
  const wrapper = mountPage(Contracts);
  await flushPromises();
  expect(mocks.contracts.list).toHaveBeenCalledWith({
    customer_segment_id: '8',
  });
  expect(mocks.contracts.show).toHaveBeenCalledWith('99');
  expect(mocks.contracts.history).toHaveBeenCalledWith('99');
  expect(wrapper.text()).toContain('SYNTHETIC-CONTRACT-99');
  wrapper.unmount();
});
it('does not render a partially fetched contract when the native history authorization denies it', async () => {
  mocks.route.query = { contractId: '99' };
  mocks.contracts.history.mockRejectedValue({ response: { status: 403 } });
  const wrapper = mountPage(Contracts);
  await flushPromises();
  expect(wrapper.text()).not.toContain('SYNTHETIC-CONTRACT-99');
  expect(mocks.alert).toHaveBeenCalled();
  wrapper.unmount();
});
it('ignores a late contract response after another exact native record was requested', async () => {
  let resolve;
  mocks.route.query = { contractId: '99' };
  mocks.contracts.show.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  const wrapper = mountPage(Contracts);
  await flushPromises();
  mocks.contracts.show.mockResolvedValue({
    data: record(100, 'CURRENT-CONTRACT-100'),
  });
  mocks.route.query.contractId = '100';
  await flushPromises();
  resolve({ data: record(99, 'STALE-CONTRACT-SECRET') });
  await flushPromises();
  expect(wrapper.text()).toContain('CURRENT-CONTRACT-100');
  expect(wrapper.text()).not.toContain('STALE-CONTRACT-SECRET');
  wrapper.unmount();
});
it('clears contract context and ignores an old-account response after the route account changes', async () => {
  let resolve;
  mocks.route.query = { contractId: '99' };
  mocks.contracts.show.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  const wrapper = mountPage(Contracts);
  await flushPromises();
  mocks.route.query = {};
  mocks.route.params.accountId = '18';
  await flushPromises();
  resolve({ data: record(99, 'OLD-ACCOUNT-SECRET') });
  await flushPromises();
  expect(wrapper.text()).not.toContain('OLD-ACCOUNT-SECRET');
  wrapper.unmount();
});
it('opens an authorized order by exact URL ID outside the list without dropping its segment filter', async () => {
  mocks.route.query = { orderId: '99', customer_segment_id: '8' };
  const wrapper = mountPage(Orders);
  await flushPromises();
  expect(mocks.orders.list).toHaveBeenCalledWith({ customer_segment_id: '8' });
  expect(mocks.orders.show).toHaveBeenCalledWith('99');
  expect(wrapper.text()).toContain('SYNTHETIC-ORDER-99');
  expect(mocks.router.replace).toHaveBeenCalledWith({
    query: { orderId: '99', customer_segment_id: '8' },
  });
  wrapper.unmount();
});
it('never substitutes a fabricated order placeholder for a denied native detail', async () => {
  mocks.route.query = { orderId: '99' };
  mocks.orders.show.mockRejectedValue({ response: { status: 403 } });
  const wrapper = mountPage(Orders);
  await flushPromises();
  expect(wrapper.text()).not.toContain('SYNTHETIC-ORDER-99');
  expect(mocks.alert).toHaveBeenCalled();
  wrapper.unmount();
});
it('ignores a stale order after route navigation selected a newer record', async () => {
  let resolve;
  mocks.route.query = { orderId: '99' };
  mocks.orders.show.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  const wrapper = mountPage(Orders);
  await flushPromises();
  mocks.orders.show.mockResolvedValue({
    data: record(100, 'CURRENT-ORDER-100'),
  });
  mocks.route.query.orderId = '100';
  await flushPromises();
  resolve({ data: record(99, 'STALE-ORDER-SECRET') });
  await flushPromises();
  expect(wrapper.text()).toContain('CURRENT-ORDER-100');
  expect(wrapper.text()).not.toContain('STALE-ORDER-SECRET');
  wrapper.unmount();
});
it('does not disclose old-account order detail after account navigation', async () => {
  let resolve;
  mocks.route.query = { orderId: '99' };
  mocks.orders.show.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  const wrapper = mountPage(Orders);
  await flushPromises();
  mocks.route.query = {};
  mocks.route.params.accountId = '18';
  await flushPromises();
  resolve({ data: record(99, 'OLD-ACCOUNT-ORDER-SECRET') });
  await flushPromises();
  expect(wrapper.text()).not.toContain('OLD-ACCOUNT-ORDER-SECRET');
  wrapper.unmount();
});
