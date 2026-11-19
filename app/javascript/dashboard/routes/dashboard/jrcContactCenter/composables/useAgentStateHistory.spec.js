import { afterEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useAgentStateHistory } from './useAgentStateHistory';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { agentStateHistory: vi.fn() },
}));
enableAutoUnmount(afterEach);
afterEach(() => vi.clearAllMocks());
const response = (account = '1', page = 1) => ({
  data: {
    account_id: account,
    items: [{ id: '9', agent_name: 'SYNTHETIC authorized actor' }],
    meta: { page, per_page: 20, total: 21, pages: 2 },
    window: {
      from: '2026-11-01',
      to: '2026-11-07',
      timezone: 'America/Sao_Paulo',
    },
  },
});
const fixture = (open = true) => {
  const accountId = ref('1');
  const enabled = ref(open);
  let history;
  const wrapper = mount(
    defineComponent({
      setup() {
        history = useAgentStateHistory({ accountId, enabled });
        return () => null;
      },
    })
  );
  return { accountId, enabled, history, wrapper };
};

describe('native operational state history lifecycle', () => {
  it('does not request protected data until the authorized popup opens', async () => {
    API.agentStateHistory.mockResolvedValue(response());
    const f = fixture(false);
    expect(API.agentStateHistory).not.toHaveBeenCalled();
    f.enabled.value = true;
    await flushPromises();
    expect(API.agentStateHistory).toHaveBeenCalledWith('1', {
      page: 1,
      per_page: 20,
    });
    expect(f.history.items.value).toEqual(response().data.items);
    expect(f.history.loading.value).toBe(false);
  });

  it('applies filters explicitly, keeps them during pagination and clears them on request', async () => {
    API.agentStateHistory.mockImplementation(async (_account, params) =>
      response('1', params.page)
    );
    const f = fixture();
    await flushPromises();
    f.history.filters.value.state = 'paused';
    f.history.filters.value.queue_id = '6';
    expect(API.agentStateHistory).toHaveBeenCalledTimes(1);
    await f.history.apply();
    await f.history.load(2);
    expect(API.agentStateHistory).toHaveBeenLastCalledWith('1', {
      state: 'paused',
      queue_id: '6',
      page: 2,
      per_page: 20,
    });
    await f.history.clear();
    expect(API.agentStateHistory).toHaveBeenLastCalledWith('1', {
      page: 1,
      per_page: 20,
    });
    expect(f.history.filters.value.state).toBe('');
  });

  it('clears previous rows during refresh and preserves a visible error without automatic retries', async () => {
    API.agentStateHistory.mockResolvedValueOnce(response());
    const f = fixture();
    await flushPromises();
    API.agentStateHistory.mockRejectedValueOnce({ response: { status: 403 } });
    await f.history.load();
    expect(f.history.items.value).toEqual([]);
    expect(f.history.meta.value).toBeNull();
    expect(f.history.failed.value).toBe(true);
    expect(API.agentStateHistory).toHaveBeenCalledTimes(2);
    API.agentStateHistory.mockResolvedValueOnce(response());
    await f.history.load();
    expect(f.history.failed.value).toBe(false);
    expect(f.history.items.value).toHaveLength(1);
  });

  it('invalidates late responses after the popup closes or permission is lost', async () => {
    let resolve;
    API.agentStateHistory.mockReturnValue(
      new Promise(done => {
        resolve = done;
      })
    );
    const f = fixture();
    f.enabled.value = false;
    resolve(response());
    await flushPromises();
    expect(f.history.items.value).toEqual([]);
    expect(f.history.meta.value).toBeNull();
    expect(f.history.loading.value).toBe(false);
  });

  it('ignores a response from a previous account even when it arrives after the new account', async () => {
    let previous;
    API.agentStateHistory.mockReturnValueOnce(
      new Promise(done => {
        previous = done;
      })
    );
    API.agentStateHistory.mockResolvedValueOnce(response('2'));
    const f = fixture();
    f.accountId.value = '2';
    await flushPromises();
    previous(response());
    await flushPromises();
    expect(f.history.meta.value).toEqual(response('2').data.meta);
    expect(API.agentStateHistory).toHaveBeenLastCalledWith('2', {
      page: 1,
      per_page: 20,
    });
    expect(f.history.failed.value).toBe(false);
  });

  it.each([
    { account_id: '2' },
    { items: null },
    { meta: { page: 2, per_page: 20 } },
    { window: {} },
  ])(
    'rejects incompatible response identity or pagination %j',
    async override => {
      API.agentStateHistory.mockResolvedValue({
        data: { ...response().data, ...override },
      });
      const f = fixture();
      await flushPromises();
      expect(f.history.items.value).toEqual([]);
      expect(f.history.failed.value).toBe(true);
    }
  );

  it('does not commit a response after the component unmounts', async () => {
    let resolve;
    API.agentStateHistory.mockReturnValue(
      new Promise(done => {
        resolve = done;
      })
    );
    const f = fixture();
    f.wrapper.unmount();
    resolve(response());
    await flushPromises();
    expect(f.history.items.value).toEqual([]);
    expect(f.history.loading.value).toBe(false);
  });
});
