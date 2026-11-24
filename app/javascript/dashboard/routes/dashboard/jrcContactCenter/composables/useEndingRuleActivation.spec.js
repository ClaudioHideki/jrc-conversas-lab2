import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useEndingRuleActivation } from './useEndingRuleActivation';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { activateEndingRule: vi.fn(), endingRuleReadiness: vi.fn() },
}));
enableAutoUnmount(afterEach);
afterEach(() => vi.unstubAllGlobals());
const key = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const revision = 'a'.repeat(64);
const accepted = () => ({
  data: {
    account_id: '1',
    reviewed_revision: revision,
    item: {
      id: '4',
      version_id: '7',
      rule_code: 'SYNTHETIC_RULE',
      activated_at: '2026-11-24T10:00:00Z',
      prospective_only: true,
    },
  },
});
const render = async () => {
  const inputs = {
    accountId: ref('1'),
    rule: ref({
      code: 'SYNTHETIC_RULE',
      active: true,
      execution_mode: 'automatic',
    }),
    revision: ref(revision),
    disabled: ref(false),
    onDenied: vi.fn(),
    onBusy: vi.fn(),
  };
  let state;
  const wrapper = mount(
    defineComponent({
      setup() {
        state = useEndingRuleActivation(inputs);
        return () => h('div');
      },
    })
  );
  await flushPromises();
  return { state, inputs, wrapper };
};
beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal('crypto', { randomUUID: vi.fn(() => key) });
  API.activateEndingRule.mockResolvedValue(accepted());
  API.endingRuleReadiness.mockResolvedValue({
    data: {
      account_id: '1',
      reviewed_revision: revision,
      last_review: null,
      applicable_review: null,
    },
  });
});

describe('explicit prospective ending rule activation', () => {
  it('reloads a persisted applicable review without sending another activation', async () => {
    API.endingRuleReadiness.mockResolvedValue({
      data: {
        account_id: '1',
        reviewed_revision: revision,
        last_review: accepted().data.item,
        applicable_review: accepted().data.item,
      },
    });
    const { state } = await render();
    expect(state.receipt.value).toEqual(accepted().data.item);
    expect(state.canSubmit.value).toBe(false);
    expect(API.activateEndingRule).not.toHaveBeenCalled();
  });

  it('shows preserved but inapplicable history without automatically reactivating it', async () => {
    API.endingRuleReadiness.mockResolvedValue({
      data: {
        account_id: '1',
        reviewed_revision: revision,
        last_review: accepted().data.item,
        applicable_review: null,
      },
    });
    const { state } = await render();
    expect(state.previousReceipt.value).toEqual(accepted().data.item);
    expect(state.receipt.value).toBeNull();
    expect(state.canSubmit.value).toBe(false);
    expect(API.activateEndingRule).not.toHaveBeenCalled();
  });

  it('does not enable activation from an unverified persisted-state response', async () => {
    API.endingRuleReadiness.mockResolvedValue({ data: { account_id: '2' } });
    const { state } = await render();
    state.reviewed.value = true;
    await state.submit();
    expect(state.error.value).toBe('LOAD_FAILED');
    expect(state.loaded.value).toBe(false);
    expect(API.activateEndingRule).not.toHaveBeenCalled();
  });

  it('never posts on mount or without explicit review', async () => {
    const { state } = await render();
    await state.submit();
    expect(API.activateEndingRule).not.toHaveBeenCalled();
    expect(state.receipt.value).toBeNull();
  });

  it('sends the reviewed current rule and revision and accepts only its matching receipt', async () => {
    const { state } = await render();
    state.reviewed.value = true;
    await state.submit();
    expect(API.activateEndingRule).toHaveBeenCalledExactlyOnceWith(
      '1',
      'SYNTHETIC_RULE',
      revision,
      key
    );
    expect(state.receipt.value).toEqual(accepted().data.item);
    expect(state.canSubmit.value).toBe(false);
  });

  it('prevents simultaneous duplicate submissions while the acknowledgement is outstanding', async () => {
    let resolve;
    API.activateEndingRule.mockReturnValue(
      new Promise(done => {
        resolve = done;
      })
    );
    const { state, inputs } = await render();
    state.reviewed.value = true;
    const pending = state.submit();
    await state.submit();
    expect(API.activateEndingRule).toHaveBeenCalledTimes(1);
    expect(inputs.onBusy).toHaveBeenLastCalledWith(true);
    resolve(accepted());
    await pending;
    expect(inputs.onBusy).toHaveBeenLastCalledWith(false);
  });

  it('retains the same idempotency key for an explicit retry after a lost response', async () => {
    API.activateEndingRule.mockRejectedValueOnce(
      new Error('SYNTHETIC lost acknowledgement')
    );
    const { state } = await render();
    state.reviewed.value = true;
    await state.submit();
    expect(state.error.value).toBe('FAILED');
    expect(API.activateEndingRule).toHaveBeenCalledTimes(1);
    await state.submit();
    expect(API.activateEndingRule.mock.calls.map(call => call[3])).toEqual([
      key,
      key,
    ]);
    expect(state.receipt.value).not.toBeNull();
  });

  it('blocks a stale review until the rule is actually reloaded rather than automatically posting again', async () => {
    API.activateEndingRule.mockRejectedValue({ response: { status: 409 } });
    const { state } = await render();
    state.reviewed.value = true;
    await state.submit();
    state.reviewed.value = true;
    await state.submit();
    expect(state.stale.value).toBe(true);
    expect(state.error.value).toBe('STALE');
    expect(API.activateEndingRule).toHaveBeenCalledTimes(1);
  });

  it.each([401, 403, 404])(
    'clears the local review and notifies its parent on denied status %i',
    async status => {
      API.activateEndingRule.mockRejectedValue({ response: { status } });
      const { state, inputs } = await render();
      state.reviewed.value = true;
      await state.submit();
      expect(inputs.onDenied).toHaveBeenCalledTimes(1);
      expect(state.reviewed.value).toBe(false);
      expect(state.receipt.value).toBeNull();
    }
  );

  it('drops a late acknowledgement after switching accounts without reusing its receipt or review', async () => {
    let resolve;
    API.activateEndingRule.mockReturnValue(
      new Promise(done => {
        resolve = done;
      })
    );
    const { state, inputs } = await render();
    state.reviewed.value = true;
    const pending = state.submit();
    inputs.accountId.value = '2';
    resolve(accepted());
    await pending;
    expect(state.receipt.value).toBeNull();
    expect(state.reviewed.value).toBe(false);
    expect(inputs.onBusy).toHaveBeenLastCalledWith(false);
  });

  it('rejects an acknowledgement with another account or an incomplete identity', async () => {
    const invalid = accepted();
    invalid.data.account_id = '2';
    API.activateEndingRule.mockResolvedValue(invalid);
    const { state } = await render();
    state.reviewed.value = true;
    await state.submit();
    expect(state.receipt.value).toBeNull();
    expect(state.error.value).toBe('FAILED');
  });

  it('invalidates review when the rule or loaded revision changes', async () => {
    const { state, inputs } = await render();
    state.reviewed.value = true;
    inputs.rule.value.code = 'SYNTHETIC_OTHER_RULE';
    expect(state.reviewed.value).toBe(false);
    state.reviewed.value = true;
    inputs.revision.value = 'b'.repeat(64);
    expect(state.reviewed.value).toBe(false);
    expect(API.activateEndingRule).not.toHaveBeenCalled();
  });

  it('does not submit an inactive, manual, disabled or unversioned rule', async () => {
    const { state, inputs } = await render();
    inputs.rule.value.active = false;
    state.reviewed.value = true;
    await state.submit();
    inputs.rule.value.active = true;
    inputs.rule.value.execution_mode = 'agent_confirmation';
    state.reviewed.value = true;
    await state.submit();
    inputs.rule.value.execution_mode = 'automatic';
    inputs.disabled.value = true;
    state.reviewed.value = true;
    await state.submit();
    inputs.disabled.value = false;
    inputs.revision.value = '';
    state.reviewed.value = true;
    await state.submit();
    expect(API.activateEndingRule).not.toHaveBeenCalled();
  });

  it('does not retain an acknowledgement after the owning editor is unmounted', async () => {
    let resolve;
    API.activateEndingRule.mockReturnValue(
      new Promise(done => {
        resolve = done;
      })
    );
    const { state, wrapper, inputs } = await render();
    state.reviewed.value = true;
    const pending = state.submit();
    wrapper.unmount();
    resolve(accepted());
    await pending;
    expect(state.receipt.value).toBeNull();
    expect(inputs.onBusy).toHaveBeenLastCalledWith(false);
  });
});
