import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useQueueCalendarRemoval } from './useQueueCalendarRemoval';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    queueCalendar: vi.fn(),
    removeQueueCalendar: vi.fn(),
  },
}));
const bindingId = '11111111-1111-4111-8111-111111111111';
const row = () => ({
  account_id: '1',
  unit_id: '10',
  queue_id: '20',
  queue_revision: 'a'.repeat(64),
  binding: { id: bindingId, calendar_digest: 'b'.repeat(64) },
});
const result = body => ({
  contract_version: 1,
  format: 'jrc-cc-queue-calendar-removal-v1',
  account_id: '1',
  unit_id: '10',
  queue_id: '20',
  idempotency_key: body.idempotency_key,
  removed_binding_id: bindingId,
  removed_calendar_digest: 'b'.repeat(64),
  queue_revision_after: 'c'.repeat(64),
  audit_id: '30',
  historical_receipt: true,
  local_only: true,
  pabx_confirmed: false,
  external_impact: 'unknown',
});
const deferred = () => {
  let resolve;
  const promise = new Promise(yes => {
    resolve = yes;
  });
  return { promise, resolve };
};
const fixture = () => {
  const context = {
    accountId: ref('1'),
    unitId: ref('10'),
    row: ref(row()),
    contextKey: ref('SYNTHETIC profile'),
    canManage: ref(true),
    validateCurrent: vi.fn(
      value =>
        value?.account_id === '1' &&
        value?.unit_id === '10' &&
        value?.queue_id === '20'
    ),
    onLock: vi.fn(),
    onCurrent: vi.fn(),
    onDenied: vi.fn(),
  };
  let state;
  mount(
    defineComponent({
      setup() {
        state = useQueueCalendarRemoval(context);
        return () => null;
      },
    })
  );
  return { state, ...context };
};
enableAutoUnmount(cleanup =>
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  })
);
beforeEach(() => {
  vi.clearAllMocks();
  API.removeQueueCalendar.mockImplementation(
    async (_account, _queue, body) => ({ data: result(body) })
  );
  API.queueCalendar.mockImplementation(async () => ({
    data: { ...row(), binding: null },
  }));
});

describe('explicit internal removal with mocked transport, not native acceptance', () => {
  it('requires separate acknowledgment before leaving an uncertain operation and never claims it was undone', async () => {
    API.removeQueueCalendar.mockRejectedValueOnce(
      new Error('SYNTHETIC unknown response')
    );
    const { state, onCurrent, onLock } = fixture();
    state.open();
    state.reviewed.value = true;
    await state.submit();
    state.abandon();
    expect(state.active.value).toBe(true);
    state.abandonReviewed.value = true;
    state.abandon();
    expect(state.active.value).toBe(false);
    expect(onLock).toHaveBeenLastCalledWith(false);
    expect(onCurrent).not.toHaveBeenCalled();
    expect(API.removeQueueCalendar).toHaveBeenCalledTimes(1);
  });

  it('keeps a failed conflict refresh manually recoverable without resubmitting the mutation', async () => {
    API.removeQueueCalendar.mockRejectedValueOnce({
      response: { status: 409 },
    });
    API.queueCalendar.mockRejectedValueOnce(
      new Error('SYNTHETIC read unavailable')
    );
    const { state, onCurrent } = fixture();
    state.open();
    state.reviewed.value = true;
    await state.submit();
    await state.reloadAfterConflict();
    expect(state.error.value).toBe('CONFLICT');
    expect(state.active.value).toBe(true);
    await state.reloadAfterConflict();
    expect(state.active.value).toBe(false);
    expect(onCurrent).toHaveBeenCalledTimes(1);
    expect(API.removeQueueCalendar).toHaveBeenCalledTimes(1);
  });
  it('requires a real current authorized binding and never loads or mutates by opening alone', () => {
    const { state, canManage, row: current, onLock } = fixture();
    canManage.value = false;
    state.open();
    expect(state.active.value).toBe(false);
    canManage.value = true;
    current.value = { ...row(), binding: null };
    state.open();
    expect(state.active.value).toBe(false);
    current.value = row();
    state.open();
    expect(onLock).toHaveBeenLastCalledWith(true);
    expect(API.queueCalendar).not.toHaveBeenCalled();
    expect(API.removeQueueCalendar).not.toHaveBeenCalled();
  });

  it('requires explicit review and sends only the reviewed queue, revision and binding identity', async () => {
    const { state, onCurrent } = fixture();
    state.open();
    await state.submit();
    expect(API.removeQueueCalendar).not.toHaveBeenCalled();
    state.reviewed.value = true;
    await state.submit();
    const sent = API.removeQueueCalendar.mock.calls[0][2];
    expect(sent).toEqual({
      unit_id: '10',
      queue_id: '20',
      binding_id: bindingId,
      expected_revision: 'a'.repeat(64),
      idempotency_key: expect.any(String),
      reviewed: true,
    });
    expect(Object.isFrozen(sent)).toBe(true);
    expect(state.receipt.value.historical_receipt).toBe(true);
    expect(state.current.value.binding).toBeNull();
    expect(onCurrent).not.toHaveBeenCalled();
    state.finish();
    expect(onCurrent).toHaveBeenCalledWith({ ...row(), binding: null });
  });

  it('does not erase a newer association on recovery of a historical successful removal', async () => {
    const newer = {
      ...row(),
      binding: { ...row().binding, id: '22222222-2222-4222-8222-222222222222' },
    };
    API.queueCalendar.mockResolvedValue({ data: newer });
    const { state, onCurrent } = fixture();
    state.open();
    state.reviewed.value = true;
    await state.submit();
    expect(state.receipt.value.removed_binding_id).toBe(bindingId);
    expect(state.current.value).toEqual(newer);
    state.finish();
    expect(onCurrent).toHaveBeenCalledWith(newer);
  });

  it('blocks duplicate submits and dismissal while its own request is in flight', async () => {
    const gate = deferred();
    API.removeQueueCalendar.mockReturnValueOnce(gate.promise);
    const { state, onLock } = fixture();
    state.open();
    state.reviewed.value = true;
    const waiting = state.submit();
    await state.submit();
    state.finish();
    expect(API.removeQueueCalendar).toHaveBeenCalledTimes(1);
    expect(state.active.value).toBe(true);
    expect(onLock).toHaveBeenLastCalledWith(true);
    gate.resolve({ data: result(state.payload.value) });
    await waiting;
  });

  it('freezes an uncertain request for manually reviewed replay without creating a new identity', async () => {
    API.removeQueueCalendar.mockRejectedValueOnce(
      new Error('SYNTHETIC lost response')
    );
    const { state } = fixture();
    state.open();
    state.reviewed.value = true;
    await state.submit();
    const sent = API.removeQueueCalendar.mock.calls[0][2];
    expect(state.error.value).toBe('UNCERTAIN');
    expect(state.reviewed.value).toBe(false);
    await state.submit();
    expect(API.removeQueueCalendar).toHaveBeenCalledTimes(1);
    state.reviewed.value = true;
    await state.submit();
    expect(API.removeQueueCalendar.mock.calls[1][2]).toBe(sent);
    expect(state.receipt.value.idempotency_key).toBe(sent.idempotency_key);
  });

  it.each([
    ['account_id', '2'],
    ['unit_id', '11'],
    ['queue_id', '21'],
    ['audit_id', '0'],
    ['removed_binding_id', '22222222-2222-4222-8222-222222222222'],
    ['removed_calendar_digest', 'f'.repeat(64)],
    ['historical_receipt', false],
    ['pabx_confirmed', true],
    ['external_impact', 'none'],
    ['queue_revision_after', 'broken'],
    ['idempotency_key', '22222222-2222-4222-8222-222222222222'],
  ])(
    'rejects unverified receipt field %s and does not infer current removal',
    async (field, value) => {
      API.removeQueueCalendar.mockImplementationOnce(
        async (_account, _queue, body) => ({
          data: { ...result(body), [field]: value },
        })
      );
      const { state, onCurrent } = fixture();
      state.open();
      state.reviewed.value = true;
      await state.submit();
      expect(state.error.value).toBe('UNCERTAIN');
      expect(state.receipt.value).toBeNull();
      expect(API.queueCalendar).not.toHaveBeenCalled();
      expect(onCurrent).not.toHaveBeenCalled();
    }
  );

  it('preserves a valid operation receipt if current state cannot be read, then retries only the read', async () => {
    API.queueCalendar.mockRejectedValueOnce(
      new Error('SYNTHETIC read unavailable')
    );
    const { state, onCurrent } = fixture();
    state.open();
    state.reviewed.value = true;
    await state.submit();
    expect(state.error.value).toBe('CURRENT_UNKNOWN');
    expect(state.receipt.value).not.toBeNull();
    state.finish();
    await state.submit();
    expect(onCurrent).not.toHaveBeenCalled();
    expect(API.removeQueueCalendar).toHaveBeenCalledTimes(1);
    await state.refresh();
    expect(state.current.value.binding).toBeNull();
    expect(API.removeQueueCalendar).toHaveBeenCalledTimes(1);
  });

  it('rejects an unauthorized current queue even after a valid historical receipt', async () => {
    API.queueCalendar.mockResolvedValueOnce({
      data: { ...row(), unit_id: '99', binding: null },
    });
    const { state, onCurrent } = fixture();
    state.open();
    state.reviewed.value = true;
    await state.submit();
    expect(state.error.value).toBe('CURRENT_UNKNOWN');
    expect(state.current.value).toBeNull();
    state.finish();
    expect(onCurrent).not.toHaveBeenCalled();
  });

  it('does not resubmit a stale removal and requires a fresh authorized read before returning to review', async () => {
    API.removeQueueCalendar.mockRejectedValueOnce({
      response: { status: 409 },
    });
    const { state, onCurrent } = fixture();
    state.open();
    state.reviewed.value = true;
    await state.submit();
    state.reviewed.value = true;
    await state.submit();
    expect(API.removeQueueCalendar).toHaveBeenCalledTimes(1);
    await state.reloadAfterConflict();
    expect(state.active.value).toBe(false);
    expect(onCurrent).toHaveBeenCalledWith({ ...row(), binding: null });
  });

  it.each([401, 403, 404])(
    'clears private state and signals denial on current authority failure %s',
    async status => {
      API.removeQueueCalendar.mockRejectedValueOnce({ response: { status } });
      const { state, onDenied, onLock } = fixture();
      state.open();
      state.reviewed.value = true;
      await state.submit();
      expect(state.active.value).toBe(false);
      expect(state.payload.value).toBeNull();
      expect(onDenied).toHaveBeenCalledTimes(1);
      expect(onLock).toHaveBeenLastCalledWith(false);
    }
  );

  it.each(['accountId', 'unitId', 'contextKey', 'canManage', 'row'])(
    'clears synchronously and ignores late mutation results after %s changes',
    async key => {
      const gate = deferred();
      API.removeQueueCalendar.mockReturnValueOnce(gate.promise);
      const context = fixture();
      const { state } = context;
      state.open();
      state.reviewed.value = true;
      const waiting = state.submit();
      const old = state.payload.value;
      context[key].value =
        { canManage: false, row: { ...row(), queue_id: '21' } }[key] ??
        'SYNTHETIC changed';
      expect(state.active.value).toBe(false);
      expect(state.payload.value).toBeNull();
      gate.resolve({ data: result(old) });
      await waiting;
      await flushPromises();
      expect(state.receipt.value).toBeNull();
      expect(API.queueCalendar).not.toHaveBeenCalled();
    }
  );
});
