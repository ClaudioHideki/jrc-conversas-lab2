import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useEndingAttemptHistory } from './useEndingAttemptHistory';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { endingAttemptHistory: vi.fn() },
}));
enableAutoUnmount(afterEach);

const row = (id = '21') => ({
  id,
  origin_id: '7',
  version_id: '8',
  rule_code: 'SYNTHETIC_RULE',
  destination_kind: 'project_task',
  request_id: '12345678-1234-4234-8234-123456789abc',
  queued_at: '2026-11-24T12:00:00Z',
  outcome: 'pending',
  result_code: null,
  finished_at: null,
  execution_id: null,
  target: null,
});
const success = () => ({
  ...row(),
  outcome: 'succeeded',
  result_code: 'completed',
  finished_at: '2026-11-24T12:01:00Z',
  execution_id: '12',
});
const page = (items = [row()], number = 1, total = items.length) => ({
  data: {
    contract_version: 1,
    account_id: '1',
    qualification_id: '5',
    call_session_id: '9',
    items,
    meta: { page: number, per_page: 20, total, pages: Math.ceil(total / 20) },
  },
});
const deferred = () => {
  let resolve;
  const promise = new Promise(accept => {
    resolve = accept;
  });
  return { promise, resolve };
};
const setup = () => {
  const accountId = ref('1');
  const qualificationId = ref('5');
  const authorityKey = ref('SYNTHETIC_AUTHORITY_A');
  let history;
  const wrapper = mount(
    defineComponent({
      setup() {
        history = useEndingAttemptHistory({
          accountId,
          qualificationId,
          authorityKey,
        });
        return () => h('div');
      },
    })
  );
  return { history, wrapper, accountId, qualificationId, authorityKey };
};

describe('Explicit native ending history reader', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    API.endingAttemptHistory.mockResolvedValue(page());
  });

  it('does not request data until the user opens the panel', () => {
    const { history } = setup();
    expect(history.opened.value).toBe(false);
    expect(history.items.value).toEqual([]);
    expect(API.endingAttemptHistory).not.toHaveBeenCalled();
  });

  it('loads exactly the current account and qualification without starting an action', async () => {
    const { history } = setup();
    await history.open();
    expect(API.endingAttemptHistory).toHaveBeenCalledExactlyOnceWith('1', '5', {
      page: 1,
    });
    expect(history.items.value).toEqual([row()]);
    expect(history.callSessionId.value).toBe('9');
    expect(history.loading.value).toBe(false);
  });

  it('replaces the page rather than appending duplicates during pagination', async () => {
    API.endingAttemptHistory.mockResolvedValueOnce(page([row()], 1, 21));
    API.endingAttemptHistory.mockResolvedValueOnce(page([row('22')], 2, 21));
    const { history } = setup();
    await history.open();
    await history.load(2);
    expect(API.endingAttemptHistory).toHaveBeenLastCalledWith('1', '5', {
      page: 2,
    });
    expect(history.items.value.map(item => item.id)).toEqual(['22']);
    expect(history.meta.value.page).toBe(2);
  });

  it.each([401, 403, 404])(
    'clears receipts on denied read status %s',
    async status => {
      const { history } = setup();
      await history.open();
      API.endingAttemptHistory.mockRejectedValueOnce({ response: { status } });
      await history.load();
      expect(history.items.value).toEqual([]);
      expect(history.callSessionId.value).toBe(null);
      expect(history.error.value).toBe('DENIED');
      expect(API.endingAttemptHistory).toHaveBeenCalledTimes(2);
    }
  );

  it('does not retry an uncertain read automatically or claim success', async () => {
    API.endingAttemptHistory.mockRejectedValueOnce(
      new Error('SYNTHETIC_NETWORK')
    );
    const { history } = setup();
    await history.open();
    await flushPromises();
    expect(history.error.value).toBe('LOAD_FAILED');
    expect(history.items.value).toEqual([]);
    expect(API.endingAttemptHistory).toHaveBeenCalledTimes(1);
  });

  it('discards a delayed response after changing the account', async () => {
    const pending = deferred();
    API.endingAttemptHistory.mockReturnValueOnce(pending.promise);
    const { history, accountId } = setup();
    const request = history.open();
    accountId.value = '2';
    pending.resolve(page());
    await request;
    expect(history.opened.value).toBe(false);
    expect(history.items.value).toEqual([]);
    expect(history.meta.value).toBe(null);
    expect(API.endingAttemptHistory).toHaveBeenCalledTimes(1);
  });

  it('discards a delayed response after changing the attendance', async () => {
    const pending = deferred();
    API.endingAttemptHistory.mockReturnValueOnce(pending.promise);
    const { history, qualificationId } = setup();
    const request = history.open();
    qualificationId.value = '6';
    pending.resolve(page());
    await request;
    expect(history.opened.value).toBe(false);
    expect(history.items.value).toEqual([]);
    expect(history.loading.value).toBe(false);
  });

  it('clears existing receipts synchronously when effective authority changes', async () => {
    const { history, authorityKey } = setup();
    await history.open();
    authorityKey.value = 'SYNTHETIC_AUTHORITY_REVOKED';
    expect(history.items.value).toEqual([]);
    expect(history.opened.value).toBe(false);
    expect(history.callSessionId.value).toBe(null);
  });

  it('does not restore receipts from an old profile response', async () => {
    const pending = deferred();
    API.endingAttemptHistory.mockReturnValueOnce(pending.promise);
    const { history, authorityKey } = setup();
    const request = history.open();
    authorityKey.value = 'SYNTHETIC_OTHER_PROFILE';
    pending.resolve(page());
    await request;
    expect(history.items.value).toEqual([]);
    expect(history.opened.value).toBe(false);
  });

  it('discards responses after the panel is unmounted', async () => {
    const pending = deferred();
    API.endingAttemptHistory.mockReturnValueOnce(pending.promise);
    const { history, wrapper } = setup();
    const request = history.open();
    wrapper.unmount();
    pending.resolve(page());
    await request;
    expect(history.items.value).toEqual([]);
    expect(history.meta.value).toBe(null);
  });

  it('rejects a response for another account', async () => {
    const response = page();
    response.data.account_id = '2';
    API.endingAttemptHistory.mockResolvedValueOnce(response);
    const { history } = setup();
    await history.open();
    expect(history.error.value).toBe('LOAD_FAILED');
    expect(history.items.value).toEqual([]);
  });

  it('rejects a response for another qualification', async () => {
    const response = page();
    response.data.qualification_id = '6';
    API.endingAttemptHistory.mockResolvedValueOnce(response);
    const { history } = setup();
    await history.open();
    expect(history.error.value).toBe('LOAD_FAILED');
    expect(history.items.value).toEqual([]);
  });

  it('does not silently deduplicate contradictory receipt identities', async () => {
    API.endingAttemptHistory.mockResolvedValueOnce(page([row(), row()]));
    const { history } = setup();
    await history.open();
    expect(history.error.value).toBe('LOAD_FAILED');
    expect(history.items.value).toEqual([]);
  });

  it('does not turn a missing private target into a guessed link', async () => {
    API.endingAttemptHistory.mockResolvedValueOnce(page([success()]));
    const { history } = setup();
    await history.open();
    expect(history.items.value[0].target).toBe(null);
    expect(history.error.value).toBe('');
  });

  it('rejects malformed destination identifiers', async () => {
    API.endingAttemptHistory.mockResolvedValueOnce(
      page([{ ...row(), target: { kind: 'project_task', id: '../1' } }])
    );
    const { history } = setup();
    await history.open();
    expect(history.error.value).toBe('LOAD_FAILED');
    expect(history.items.value).toEqual([]);
  });

  it('accepts an authorized native task reference without adding private fields', async () => {
    const target = { kind: 'project_task', id: '17', project_id: '18' };
    API.endingAttemptHistory.mockResolvedValueOnce(
      page([{ ...success(), target }])
    );
    const { history } = setup();
    await history.open();
    expect(history.items.value[0].target).toEqual(target);
    expect(history.error.value).toBe('');
  });

  it('rejects a claimed success with no native execution receipt', async () => {
    API.endingAttemptHistory.mockResolvedValueOnce(
      page([{ ...success(), execution_id: null }])
    );
    const { history } = setup();
    await history.open();
    expect(history.error.value).toBe('LOAD_FAILED');
    expect(history.items.value).toEqual([]);
  });

  it('rejects an unknown refusal classification instead of exposing an untranslated error', async () => {
    API.endingAttemptHistory.mockResolvedValueOnce(
      page([{ ...success(), outcome: 'blocked', result_code: 'PRIVATE_ERROR' }])
    );
    const { history } = setup();
    await history.open();
    expect(history.error.value).toBe('LOAD_FAILED');
    expect(history.items.value).toEqual([]);
  });

  it('rejects an unsupported state instead of rendering it as operational success', async () => {
    API.endingAttemptHistory.mockResolvedValueOnce(
      page([{ ...row(), outcome: 'UNKNOWN_SUCCESS' }])
    );
    const { history } = setup();
    await history.open();
    expect(history.error.value).toBe('LOAD_FAILED');
    expect(history.items.value).toEqual([]);
  });

  it('rejects an unbounded response even if its metadata claims a small page', async () => {
    API.endingAttemptHistory.mockResolvedValueOnce(
      page(Array.from({ length: 21 }, (_, index) => row(String(index + 1))))
    );
    const { history } = setup();
    await history.open();
    expect(history.error.value).toBe('LOAD_FAILED');
    expect(history.items.value).toEqual([]);
  });

  it('closing the panel clears data and invalidates its pending request', async () => {
    const pending = deferred();
    API.endingAttemptHistory.mockReturnValueOnce(pending.promise);
    const { history } = setup();
    const request = history.open();
    history.close();
    pending.resolve(page());
    await request;
    expect(history.opened.value).toBe(false);
    expect(history.items.value).toEqual([]);
    expect(history.loading.value).toBe(false);
  });
});
