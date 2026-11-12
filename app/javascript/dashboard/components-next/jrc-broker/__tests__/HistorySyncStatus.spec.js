import { mount, flushPromises } from '@vue/test-utils';
import HistorySyncStatus from '../HistorySyncStatus.vue';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';

vi.mock('dashboard/api/jrcBroker', () => ({ createJrcBrokerApi: vi.fn() }));
let wrapper;
let api;
const counts = {
  chats: 2,
  capturedMessages: 6,
  persistedMessages: 6,
  duplicateMessages: 0,
  projectedMessages: 4,
  pendingMedia: 2,
  verifiedMedia: 4,
  unavailableMedia: 0,
  blockedRecords: 0,
};
const value = {
  schemaVersion: 2,
  accountId: 1,
  inboxId: 7,
  run: {
    state: 'RUNNING',
    capture: 'CAPTURING',
    persistence: 'RUNNING',
    projection: 'RUNNING',
    sourceTotalKnown: false,
    counts,
  },
};
beforeEach(() => {
  api = { historySync: vi.fn().mockResolvedValue(value) };
  createJrcBrokerApi.mockReturnValue(api);
});
afterEach(() => wrapper?.unmount());
it('keeps capture, persistence, central receipts and pending media separate without claiming 100 percent', async () => {
  wrapper = mount(HistorySyncStatus, { props: { accountId: 1, inboxId: 7 } });
  await flushPromises();
  expect(wrapper.text()).toContain('6');
  expect(wrapper.text()).toContain('4');
  expect(wrapper.find('[role="progressbar"]').exists()).toBe(false);
  expect(api.historySync).toHaveBeenCalledWith(7, expect.any(AbortSignal));
});
it('clears progress and refuses a late response after changing account or inbox', async () => {
  let finish;
  api.historySync.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  wrapper = mount(HistorySyncStatus, { props: { accountId: 1, inboxId: 7 } });
  await wrapper.setProps({ accountId: 2, inboxId: 8 });
  api.historySync.mockResolvedValue({
    ...value,
    accountId: 2,
    inboxId: 8,
    run: null,
  });
  finish(value);
  await flushPromises();
  expect(wrapper.find('dl').exists()).toBe(false);
});
it('does not render counts from another inbox', async () => {
  api.historySync.mockResolvedValue({ ...value, inboxId: 8 });
  wrapper = mount(HistorySyncStatus, { props: { accountId: 1, inboxId: 7 } });
  await flushPromises();
  expect(wrapper.find('dl').exists()).toBe(false);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
});
