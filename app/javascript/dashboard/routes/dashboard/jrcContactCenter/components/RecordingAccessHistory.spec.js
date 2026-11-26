import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import RecordingAccessHistory from './RecordingAccessHistory.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { recordingAccessHistory: vi.fn() },
}));
enableAutoUnmount(afterEach);
const create = () =>
  mount(RecordingAccessHistory, { props: { accountId: 1, recordingId: 15 } });
const row = {
  id: '88',
  created_at: '2026-11-26T12:00:00Z',
  actor_id: '4',
  operation: 'reproduce',
  request_id: 'SYNTHETIC-safe-correlation',
};
const response = (overrides = {}) => ({
  data: {
    account_id: '1',
    recording_id: '15',
    timezone: 'America/Sao_Paulo',
    items: [row],
    meta: { page: 1, pages: 1, total: 1, per_page: 20 },
    ...overrides,
  },
});
beforeEach(() => {
  vi.clearAllMocks();
  API.recordingAccessHistory.mockResolvedValue(response());
});

describe('native scoped recording access history', () => {
  it('loads only the selected native recording and uses the returned account timezone', async () => {
    const wrapper = create();
    await flushPromises();
    expect(API.recordingAccessHistory).toHaveBeenCalledWith('1', '15', {
      page: 1,
      per_page: 20,
    });
    expect(wrapper.get('[data-recording-audit-row="88"]').text()).toContain(
      '09:00:00'
    );
    expect(wrapper.text()).toContain('America/Sao_Paulo');
    expect(wrapper.text()).toContain('#4');
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.REPRODUCE'
    );
    expect(wrapper.find('[data-recording-audit-empty]').exists()).toBe(false);
  });

  it('does not turn a server failure into an empty history and explicitly retries the failed page', async () => {
    API.recordingAccessHistory.mockResolvedValueOnce(
      response({ meta: { page: 1, pages: 2, total: 21 } })
    );
    const wrapper = create();
    await flushPromises();
    API.recordingAccessHistory.mockRejectedValueOnce({
      response: { status: 500 },
    });
    await wrapper.get('nav button:last-child').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'ACCESS_HISTORY.ERROR'
    );
    expect(wrapper.find('[data-recording-audit-empty]').exists()).toBe(false);
    API.recordingAccessHistory.mockResolvedValueOnce(
      response({ items: [], meta: { page: 2, pages: 1, total: 1 } })
    );
    await wrapper.get('[data-recording-audit-retry]').trigger('click');
    await flushPromises();
    expect(API.recordingAccessHistory).toHaveBeenLastCalledWith('1', '15', {
      page: 2,
      per_page: 20,
    });
    expect(wrapper.get('nav button:first-child').element.disabled).toBe(false);
    expect(wrapper.get('nav button:last-child').element.disabled).toBe(true);
  });

  it('uses separate authorized pages without retaining the previous page rows', async () => {
    API.recordingAccessHistory.mockResolvedValueOnce(
      response({ meta: { page: 1, pages: 2, total: 21 } })
    );
    const wrapper = create();
    await flushPromises();
    API.recordingAccessHistory.mockResolvedValueOnce(
      response({
        items: [{ ...row, id: '89', operation: 'download' }],
        meta: { page: 2, pages: 2, total: 21 },
      })
    );
    await wrapper.get('nav button:last-child').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-recording-audit-row="88"]').exists()).toBe(
      false
    );
    expect(wrapper.get('[data-recording-audit-row="89"]').text()).toContain(
      'ACCESS_HISTORY.DOWNLOAD'
    );
  });

  it('withdraws the prior account rows and ignores a late response when selection changes', async () => {
    let completeFirst;
    API.recordingAccessHistory.mockReturnValueOnce(
      new Promise(resolve => {
        completeFirst = resolve;
      })
    );
    const wrapper = create();
    API.recordingAccessHistory.mockResolvedValueOnce(
      response({ account_id: '2', recording_id: '16', items: [] })
    );
    await wrapper.setProps({ accountId: 2, recordingId: 16 });
    await flushPromises();
    completeFirst(response());
    await flushPromises();
    expect(API.recordingAccessHistory).toHaveBeenCalledTimes(2);
    expect(API.recordingAccessHistory).toHaveBeenLastCalledWith('2', '16', {
      page: 1,
      per_page: 20,
    });
    expect(wrapper.find('[data-recording-audit-row="88"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-recording-audit-empty]').exists()).toBe(true);
  });

  it.each([401, 403, 404])(
    'shows the actual unavailable authority status %i without exposing rows',
    async status => {
      API.recordingAccessHistory.mockRejectedValueOnce({
        response: { status },
      });
      const wrapper = create();
      await flushPromises();
      expect(wrapper.get('[role="alert"]').text()).toContain(
        status === 404 ? 'ACCESS_HISTORY.UNAVAILABLE' : 'ACCESS_HISTORY.DENIED'
      );
      expect(wrapper.find('[data-recording-audit-row]').exists()).toBe(false);
      expect(wrapper.find('[data-recording-audit-empty]').exists()).toBe(false);
    }
  );

  it.each([
    { account_id: '2' },
    { recording_id: '16' },
    { timezone: 'Invalid/Timezone' },
    { items: [{ ...row, operation: 'unknown-private-operation' }] },
    { items: [{ ...row, created_at: 'not-a-date' }] },
  ])(
    'rejects a changed recording identity, invalid time or unknown operation: %j',
    async invalid => {
      API.recordingAccessHistory.mockResolvedValueOnce(response(invalid));
      const wrapper = create();
      await flushPromises();
      expect(wrapper.get('[role="alert"]').text()).toContain(
        'ACCESS_HISTORY.ERROR'
      );
      expect(wrapper.find('[data-recording-audit-row]').exists()).toBe(false);
    }
  );

  it('ignores an outstanding response after the authorized popup is unmounted', async () => {
    let complete;
    API.recordingAccessHistory.mockReturnValueOnce(
      new Promise(resolve => {
        complete = resolve;
      })
    );
    const wrapper = create();
    wrapper.unmount();
    complete(response());
    await flushPromises();
    expect(API.recordingAccessHistory).toHaveBeenCalledTimes(1);
  });
});
