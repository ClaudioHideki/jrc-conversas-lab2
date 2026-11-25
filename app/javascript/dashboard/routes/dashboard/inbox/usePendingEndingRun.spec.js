import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { usePendingEndingRun } from './usePendingEndingRun';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { runPendingEndingAttempt: vi.fn() },
}));
enableAutoUnmount(afterEach);

const row = () => ({
  id: '21',
  version_id: '8',
  rule_code: 'SYNTHETIC_RULE',
  request_id: '12345678-1234-4234-8234-123456789abc',
  outcome: 'pending',
  can_reprocess_pending: true,
});
const acknowledgement = (extra = {}) => ({
  data: {
    account_id: '1',
    qualification_id: '5',
    attempt_id: '21',
    outcome: 'succeeded',
    result_code: 'completed',
    ...extra,
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
  const enabled = ref(true);
  const onComplete = vi.fn().mockResolvedValue();
  const onDenied = vi.fn(() => {
    enabled.value = false;
  });
  let operation;
  const wrapper = mount(
    defineComponent({
      setup() {
        operation = usePendingEndingRun({
          accountId,
          qualificationId,
          authorityKey,
          enabled,
          onComplete,
          onDenied,
        });
        return () => h('div');
      },
    })
  );
  return {
    operation,
    accountId,
    qualificationId,
    authorityKey,
    enabled,
    onComplete,
    onDenied,
    wrapper,
  };
};

describe('Explicit selected pending operation lifecycle', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    API.runPendingEndingAttempt.mockResolvedValue(acknowledgement());
  });

  it('does not POST on mount, selection or absent explicit review', async () => {
    const { operation } = setup();
    operation.open(row());
    await operation.submit();
    expect(operation.selected.value.id).toBe('21');
    expect(operation.canSubmit.value).toBe(false);
    expect(API.runPendingEndingAttempt).not.toHaveBeenCalled();
  });

  it('posts only the selected immutable identity and literal confirmation, then reads actual history', async () => {
    const { operation, onComplete } = setup();
    operation.open({
      ...row(),
      user_id: '900',
      unit_id: '800',
      private_template: 'SYNTHETIC_PRIVATE',
    });
    operation.reviewed.value = true;
    await operation.submit();
    expect(API.runPendingEndingAttempt).toHaveBeenCalledOnce();
    expect(API.runPendingEndingAttempt).toHaveBeenCalledWith('1', '5', '21', {
      confirmed: true,
      expected_request_key: row().request_id,
      expected_version_id: '8',
    });
    expect(operation.selected.value).toBeNull();
    expect(operation.busy.value).toBe(false);
    expect(onComplete).toHaveBeenCalledOnce();
  });

  it('blocks a second click while the first request is unresolved', async () => {
    const pending = deferred();
    API.runPendingEndingAttempt.mockReturnValue(pending.promise);
    const { operation } = setup();
    operation.open(row());
    operation.reviewed.value = true;
    const first = operation.submit();
    await operation.submit();
    expect(API.runPendingEndingAttempt).toHaveBeenCalledOnce();
    pending.resolve(acknowledgement());
    await first;
    expect(operation.busy.value).toBe(false);
  });

  it('does not select terminal or currently unauthorized operations', () => {
    const { operation } = setup();
    operation.open({
      ...row(),
      outcome: 'succeeded',
      can_reprocess_pending: false,
    });
    expect(operation.selected.value).toBeNull();
    operation.open({ ...row(), can_reprocess_pending: false });
    expect(operation.selected.value).toBeNull();
    expect(API.runPendingEndingAttempt).not.toHaveBeenCalled();
  });

  it('keeps an uncertain acknowledgement explicit without fabricating an outcome or retrying automatically', async () => {
    API.runPendingEndingAttempt.mockRejectedValue(
      new Error('SYNTHETIC acknowledgement lost')
    );
    const { operation, onComplete } = setup();
    operation.open(row());
    operation.reviewed.value = true;
    await operation.submit();
    expect(operation.error.value).toBe('UNKNOWN');
    expect(operation.selected.value.id).toBe('21');
    expect(operation.reviewed.value).toBe(false);
    expect(onComplete).not.toHaveBeenCalled();
    expect(API.runPendingEndingAttempt).toHaveBeenCalledOnce();
  });

  it('retains the exact immutable key for a second explicitly reviewed request after an uncertain reply', async () => {
    API.runPendingEndingAttempt.mockRejectedValueOnce(
      new Error('SYNTHETIC uncertain reply')
    );
    const { operation } = setup();
    operation.open(row());
    operation.reviewed.value = true;
    await operation.submit();
    operation.reviewed.value = true;
    await operation.submit();
    expect(API.runPendingEndingAttempt.mock.calls[1]).toEqual(
      API.runPendingEndingAttempt.mock.calls[0]
    );
    expect(operation.selected.value).toBeNull();
  });

  it('reads a conflict result without sending another POST or silently updating the reviewed version', async () => {
    API.runPendingEndingAttempt.mockRejectedValue({
      response: { status: 409 },
    });
    const { operation, onComplete } = setup();
    operation.open(row());
    operation.reviewed.value = true;
    await operation.submit();
    expect(operation.error.value).toBe('CHANGED');
    expect(operation.selected.value).toBeNull();
    expect(onComplete).toHaveBeenCalledOnce();
    expect(API.runPendingEndingAttempt).toHaveBeenCalledOnce();
  });

  it.each([401, 403, 404])(
    'clears the private selection and invokes denial on HTTP%s',
    async status => {
      API.runPendingEndingAttempt.mockRejectedValue({ response: { status } });
      const { operation, onDenied, onComplete } = setup();
      operation.open(row());
      operation.reviewed.value = true;
      await operation.submit();
      expect(operation.selected.value).toBeNull();
      expect(operation.busy.value).toBe(false);
      expect(operation.error.value).toBe('DENIED');
      expect(onDenied).toHaveBeenCalledOnce();
      expect(onComplete).not.toHaveBeenCalled();
    }
  );

  it('does not confuse a bounded native failure with successful task creation', async () => {
    API.runPendingEndingAttempt.mockResolvedValue(
      acknowledgement({ outcome: 'failed', result_code: 'destination_failure' })
    );
    const { operation, onComplete } = setup();
    operation.open(row());
    operation.reviewed.value = true;
    await operation.submit();
    expect(operation.error.value).toBe('NATIVE_REFUSAL');
    expect(operation.selected.value).toBeNull();
    expect(onComplete).toHaveBeenCalledOnce();
  });

  it('rejects an acknowledgement of another account rather than refreshing it as success', async () => {
    API.runPendingEndingAttempt.mockResolvedValue(
      acknowledgement({ account_id: '99' })
    );
    const { operation, onComplete } = setup();
    operation.open(row());
    operation.reviewed.value = true;
    await operation.submit();
    expect(operation.error.value).toBe('UNKNOWN');
    expect(onComplete).not.toHaveBeenCalled();
  });

  it('clears a reviewed selection synchronously on account, attendance or authority change', () => {
    const { operation, accountId, qualificationId, authorityKey } = setup();
    operation.open(row());
    accountId.value = '2';
    expect(operation.selected.value).toBeNull();
    operation.open(row());
    qualificationId.value = '6';
    expect(operation.selected.value).toBeNull();
    operation.open(row());
    authorityKey.value = 'SYNTHETIC_AUTHORITY_B';
    expect(operation.selected.value).toBeNull();
    expect(API.runPendingEndingAttempt).not.toHaveBeenCalled();
  });

  it('ignores an old successful reply after the attendance changed', async () => {
    const pending = deferred();
    API.runPendingEndingAttempt.mockReturnValue(pending.promise);
    const { operation, qualificationId, onComplete } = setup();
    operation.open(row());
    operation.reviewed.value = true;
    const first = operation.submit();
    qualificationId.value = '6';
    pending.resolve(acknowledgement());
    await first;
    expect(operation.selected.value).toBeNull();
    expect(operation.error.value).toBe('');
    expect(onComplete).not.toHaveBeenCalled();
  });

  it('clears an unavailable panel and ignores a late response after unmount', async () => {
    const pending = deferred();
    API.runPendingEndingAttempt.mockReturnValue(pending.promise);
    const { operation, enabled, wrapper, onComplete } = setup();
    operation.open(row());
    enabled.value = false;
    expect(operation.selected.value).toBeNull();
    enabled.value = true;
    operation.open(row());
    operation.reviewed.value = true;
    const first = operation.submit();
    wrapper.unmount();
    pending.resolve(acknowledgement());
    await first;
    await flushPromises();
    expect(onComplete).not.toHaveBeenCalled();
    expect(operation.selected.value).toBeNull();
  });
});
