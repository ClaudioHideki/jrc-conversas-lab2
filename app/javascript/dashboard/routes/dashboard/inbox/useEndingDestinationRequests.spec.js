import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useEndingDestinationRequests } from './useEndingDestinationRequests';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    manualEndingActions: vi.fn(),
    requestEndingDestination: vi.fn(),
    retryEndingDestination: vi.fn(),
    resumeEndingDestination: vi.fn(),
  },
}));
enableAutoUnmount(afterEach);
afterEach(() => vi.unstubAllGlobals());
const newKey = '12345678-1234-4234-8234-123456789abc';
const previousKey = '87654321-4321-4321-8321-987654321abc';
const row = () => ({
  origin_id: '7',
  readiness_id: '8',
  version_id: '9',
  rule_code: 'SYNTHETIC_SELECTED_RULE',
  destination_kind: 'crm',
  operation: 'create_lead',
  rule_sha256: 'a'.repeat(64),
});
const typed = (overrides = {}) => ({
  ...row(),
  id: 'typed:11',
  ledger: 'typed',
  attempt_id: '11',
  request_id: previousKey,
  outcome: 'failed',
  can_retry_selected: true,
  can_resume_pending: false,
  ...overrides,
});
const page = (items = [row()]) => ({
  data: {
    contract_version: 1,
    account_id: '1',
    qualification_id: '5',
    items,
    meta: {
      page: 1,
      per_page: 20,
      total: items.length,
      pages: items.length ? 1 : 0,
    },
  },
});
const ack = (key = newKey, attempt = '12') => ({
  status: 202,
  data: {
    contract_version: 1,
    account_id: '1',
    qualification_id: '5',
    ledger: 'typed',
    attempt_id: attempt,
    request_id: key,
    status: 'accepted',
    execution_confirmed: false,
  },
});
const deferred = () => {
  let resolve;
  const promise = new Promise(accept => {
    resolve = accept;
  });
  return { promise, resolve };
};
const setup = (initialEnabled = true) => {
  const accountId = ref('1');
  const qualificationId = ref('5');
  const authorityKey = ref('SYNTHETIC_ORIGINAL_AUTHORITY');
  const enabled = ref(initialEnabled);
  const onAccepted = vi.fn();
  const onDenied = vi.fn();
  let actions;
  mount(
    defineComponent({
      setup() {
        actions = useEndingDestinationRequests({
          accountId,
          qualificationId,
          authorityKey,
          enabled,
          onAccepted,
          onDenied,
        });
        return () => h('div');
      },
    })
  );
  return {
    actions,
    accountId,
    qualificationId,
    authorityKey,
    enabled,
    onAccepted,
    onDenied,
  };
};

describe('Explicit original-agent destination intent UI', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubGlobal('crypto', { randomUUID: vi.fn(() => newKey) });
    API.manualEndingActions.mockResolvedValue(page());
    API.requestEndingDestination.mockResolvedValue(ack());
    API.retryEndingDestination.mockResolvedValue(ack());
    API.resumeEndingDestination.mockResolvedValue(ack(previousKey, '11'));
  });

  it('does not read or write until the containing history is opened', async () => {
    const { actions, enabled } = setup(false);
    await flushPromises();
    expect(API.manualEndingActions).not.toHaveBeenCalled();
    enabled.value = true;
    await flushPromises();
    expect(actions.items.value).toEqual([row()]);
    expect(API.requestEndingDestination).not.toHaveBeenCalled();
    expect(API.retryEndingDestination).not.toHaveBeenCalled();
  });

  it('requires a separate explicit review before registering one selected manual action', async () => {
    const { actions, onAccepted } = setup();
    await flushPromises();
    actions.openManual(row());
    await actions.submit();
    expect(API.requestEndingDestination).not.toHaveBeenCalled();
    actions.reviewed.value = true;
    await actions.submit();
    expect(API.requestEndingDestination).toHaveBeenCalledExactlyOnceWith(
      '1',
      '5',
      {
        origin_id: '7',
        rule_code: 'SYNTHETIC_SELECTED_RULE',
        destination_kind: 'crm',
        request_key: newKey,
        review: {
          confirmed: true,
          expected_readiness_id: '8',
          expected_version_id: '9',
          expected_rule_sha256: 'a'.repeat(64),
        },
      }
    );
    expect(onAccepted).toHaveBeenCalledTimes(1);
    expect(actions.recorded.value).toBe(true);
  });

  it('blocks a second click while the same selected request is in flight', async () => {
    const response = deferred();
    API.requestEndingDestination.mockReturnValueOnce(response.promise);
    const { actions } = setup();
    await flushPromises();
    actions.openManual(row());
    actions.reviewed.value = true;
    const first = actions.submit();
    await actions.submit();
    expect(API.requestEndingDestination).toHaveBeenCalledTimes(1);
    response.resolve(ack());
    await first;
  });

  it('preserves the same UUID after an uncertain response and requires another review instead of automatic retry', async () => {
    API.requestEndingDestination.mockRejectedValueOnce(
      new Error('SYNTHETIC_UNCERTAIN_ACK')
    );
    const { actions } = setup();
    await flushPromises();
    actions.openManual(row());
    actions.reviewed.value = true;
    await actions.submit();
    expect(actions.error.value).toBe('UNKNOWN');
    expect(actions.reviewed.value).toBe(false);
    expect(API.requestEndingDestination).toHaveBeenCalledTimes(1);
    actions.reviewed.value = true;
    await actions.submit();
    expect(
      API.requestEndingDestination.mock.calls.map(call => call[2].request_key)
    ).toEqual([newKey, newKey]);
    expect(crypto.randomUUID).toHaveBeenCalledTimes(1);
  });

  it('retains the UUID when cancelling and reopening the same reviewed selection', async () => {
    const { actions } = setup();
    await flushPromises();
    actions.openManual(row());
    const key = actions.selected.value.new_request_id;
    actions.cancel();
    actions.openManual(row());
    expect(actions.selected.value.new_request_id).toBe(key);
    expect(actions.reviewed.value).toBe(false);
    expect(API.requestEndingDestination).not.toHaveBeenCalled();
  });

  it('registers only one new retry using the exact reviewed failed predecessor', async () => {
    const { actions } = setup();
    await flushPromises();
    actions.openRetry(typed());
    actions.reviewed.value = true;
    await actions.submit();
    expect(API.retryEndingDestination).toHaveBeenCalledExactlyOnceWith(
      '1',
      '5',
      '11',
      {
        request_key: newKey,
        review: {
          confirmed: true,
          expected_readiness_id: '8',
          expected_version_id: '9',
          expected_rule_sha256: 'a'.repeat(64),
          expected_request_id: previousKey,
        },
      }
    );
    expect(API.requestEndingDestination).not.toHaveBeenCalled();
  });

  it('resumes the same still-pending delivery without creating another request UUID or terminal retry', async () => {
    const { actions } = setup();
    await flushPromises();
    actions.openResume(
      typed({
        outcome: 'pending',
        can_resume_pending: true,
        can_retry_selected: false,
      })
    );
    actions.reviewed.value = true;
    await actions.submit();
    expect(API.resumeEndingDestination).toHaveBeenCalledTimes(1);
    expect(API.resumeEndingDestination.mock.calls[0][2]).toBe('11');
    expect(
      API.resumeEndingDestination.mock.calls[0][3].expected_request_id
    ).toBe(previousKey);
    expect(crypto.randomUUID).not.toHaveBeenCalled();
    expect(API.retryEndingDestination).not.toHaveBeenCalled();
  });

  it('never exposes selected execution for a succeeded or legacy row with contradictory hints', async () => {
    const { actions } = setup();
    await flushPromises();
    actions.openRetry(typed({ outcome: 'succeeded' }));
    expect(actions.selected.value).toBe(null);
    actions.openRetry(typed({ ledger: 'legacy' }));
    expect(actions.selected.value).toBe(null);
    actions.openResume(typed({ outcome: 'failed', can_resume_pending: true }));
    expect(actions.selected.value).toBe(null);
    expect(API.retryEndingDestination).not.toHaveBeenCalled();
    expect(API.resumeEndingDestination).not.toHaveBeenCalled();
  });

  it('does not claim an effect from an acknowledgement that falsely reports execution success', async () => {
    API.requestEndingDestination.mockResolvedValueOnce({
      ...ack(),
      data: { ...ack().data, execution_confirmed: true, status: 'succeeded' },
    });
    const { actions, onAccepted } = setup();
    await flushPromises();
    actions.openManual(row());
    actions.reviewed.value = true;
    await actions.submit();
    expect(actions.recorded.value).toBe(false);
    expect(actions.error.value).toBe('UNKNOWN');
    expect(onAccepted).not.toHaveBeenCalled();
  });

  it('requires a fresh read after a stale review conflict instead of resubmitting automatically', async () => {
    API.requestEndingDestination.mockRejectedValueOnce({
      response: { status: 409 },
    });
    const { actions } = setup();
    await flushPromises();
    actions.openManual(row());
    actions.reviewed.value = true;
    await actions.submit();
    actions.reviewed.value = true;
    expect(actions.error.value).toBe('CHANGED');
    expect(actions.canSubmit.value).toBe(false);
    expect(API.requestEndingDestination).toHaveBeenCalledTimes(1);
  });

  it('clears a selection when the native API denies the current original-agent action', async () => {
    API.requestEndingDestination.mockRejectedValueOnce({
      response: { status: 403 },
    });
    const { actions, onDenied } = setup();
    await flushPromises();
    actions.openManual(row());
    actions.reviewed.value = true;
    await actions.submit();
    expect(actions.selected.value).toBe(null);
    expect(actions.items.value).toEqual([]);
    expect(actions.error.value).toBe('DENIED');
    expect(onDenied).toHaveBeenCalledTimes(1);
  });

  it('discards an old acknowledgement after the effective profile changes', async () => {
    const response = deferred();
    API.requestEndingDestination.mockReturnValueOnce(response.promise);
    const { actions, authorityKey, onAccepted } = setup();
    await flushPromises();
    actions.openManual(row());
    actions.reviewed.value = true;
    const pending = actions.submit();
    authorityKey.value = 'SYNTHETIC_DIFFERENT_PROFILE';
    expect(actions.selected.value).toBe(null);
    response.resolve(ack());
    await pending;
    expect(onAccepted).not.toHaveBeenCalled();
    expect(actions.recorded.value).toBe(false);
  });

  it('does not restore another account from a delayed manual-action preview', async () => {
    const response = deferred();
    API.manualEndingActions.mockReturnValueOnce(response.promise);
    const { actions, accountId } = setup();
    accountId.value = '2';
    response.resolve(page());
    await flushPromises();
    expect(actions.items.value).toEqual([]);
    expect(actions.recorded.value).toBe(false);
  });

  it('refuses to prepare a mutation if a secure UUID source is unavailable', async () => {
    vi.stubGlobal('crypto', {});
    const { actions } = setup();
    await flushPromises();
    actions.openManual(row());
    expect(actions.error.value).toBe('UNAVAILABLE');
    expect(actions.selected.value).toBe(null);
    expect(API.requestEndingDestination).not.toHaveBeenCalled();
  });
});
