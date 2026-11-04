import { mount, flushPromises } from '@vue/test-utils';
import ConnectionInsights from '../ConnectionInsights.vue';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';

vi.mock('dashboard/api/jrcBroker', () => ({ createJrcBrokerApi: vi.fn() }));
let wrapper;
let api;
beforeEach(() => {
  api = { connectionSummary: vi.fn().mockResolvedValue({ metrics: null }) };
  createJrcBrokerApi.mockReturnValue(api);
});
afterEach(() => wrapper?.unmount());

it('renders persisted values and nulls without treating resolution as active handling or inventing eligible agents', async () => {
  api.connectionSummary.mockResolvedValue({
    metrics: {
      conversations_count: 0,
      avg_first_response_time: 95,
      avg_resolution_time: 3900,
      eligible_agents: null,
    },
  });
  wrapper = mount(ConnectionInsights, { props: { accountId: 1, inboxId: 7 } });
  await flushPromises();
  expect(wrapper.findAll('dd').map(item => item.text())).toEqual([
    '0',
    '1m 35s',
    '1h 5m',
    'No data',
  ]);
  expect(wrapper.text()).toContain('not active handling time');
  expect(api.connectionSummary).toHaveBeenCalledWith(
    7,
    expect.any(AbortSignal)
  );
});

it('shows restricted metrics without invented zero counts', async () => {
  wrapper = mount(ConnectionInsights, { props: { accountId: 1, inboxId: 7 } });
  await flushPromises();
  expect(wrapper.text()).toContain('reporting access');
  expect(wrapper.find('dl').exists()).toBe(false);
});

it('aborts account reads and rejects late old-account metrics', async () => {
  let finish;
  api.connectionSummary.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  wrapper = mount(ConnectionInsights, { props: { accountId: 1, inboxId: 7 } });
  const signal = api.connectionSummary.mock.calls[0][1];
  await wrapper.setProps({ accountId: 2, inboxId: 8 });
  await flushPromises();
  finish({ metrics: { conversations_count: 99123 } });
  await flushPromises();
  expect(signal.aborted).toBe(true);
  expect(wrapper.text()).not.toContain('99,123');
  expect(wrapper.find('dl').exists()).toBe(false);
});
