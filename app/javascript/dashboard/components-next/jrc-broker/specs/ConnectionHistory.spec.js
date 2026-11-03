import { mount, flushPromises } from '@vue/test-utils';
import ConnectionHistory from '../ConnectionHistory.vue';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';

vi.mock('dashboard/api/jrcBroker', () => ({ createJrcBrokerApi: vi.fn() }));

let wrapper;
afterEach(() => wrapper?.unmount());

it('loads the next cursor and resets pagination when filtering by an event', async () => {
  const connectionHistory = vi
    .fn()
    .mockResolvedValueOnce({
      data: [
        {
          id: 5,
          event_type: 'CONNECTED',
          occurred_at: '2026-11-02T12:00:00Z',
          user_id: 4,
          metadata: {},
        },
      ],
      next_cursor: 5,
    })
    .mockResolvedValueOnce({
      data: [
        {
          id: 2,
          event_type: 'QR_EXPIRED',
          occurred_at: '2026-11-01T12:00:00Z',
          user_id: null,
          metadata: {},
        },
      ],
      next_cursor: null,
    })
    .mockResolvedValueOnce({ data: [], next_cursor: null });
  createJrcBrokerApi.mockReturnValue({ connectionHistory });
  wrapper = mount(ConnectionHistory, { props: { accountId: 1, inboxId: 7 } });
  await flushPromises();
  expect(wrapper.text()).toContain('Connected');
  await wrapper.get('[data-testid="history-more"]').trigger('click');
  await flushPromises();
  expect(connectionHistory).toHaveBeenLastCalledWith(
    7,
    { before: 5, event_type: '' },
    expect.any(AbortSignal)
  );
  expect(wrapper.findAll('li')).toHaveLength(2);
  await wrapper.get('select').setValue('SESSION_FAILED');
  await flushPromises();
  expect(connectionHistory).toHaveBeenLastCalledWith(
    7,
    { before: null, event_type: 'SESSION_FAILED' },
    expect.any(AbortSignal)
  );
  expect(wrapper.findAll('li')).toHaveLength(0);
});

it('clears previously visible events if access is revoked while loading another page', async () => {
  const connectionHistory = vi
    .fn()
    .mockResolvedValueOnce({
      data: [{ id: 5, event_type: 'CONNECTED', metadata: {} }],
      next_cursor: 5,
    })
    .mockRejectedValueOnce({ response: { status: 403 } });
  createJrcBrokerApi.mockReturnValue({ connectionHistory });
  wrapper = mount(ConnectionHistory, { props: { accountId: 1, inboxId: 7 } });
  await flushPromises();
  await wrapper.get('[data-testid="history-more"]').trigger('click');
  await flushPromises();
  expect(wrapper.findAll('li')).toHaveLength(0);
  expect(wrapper.get('[role="alert"]').text()).toContain('no longer available');
});
