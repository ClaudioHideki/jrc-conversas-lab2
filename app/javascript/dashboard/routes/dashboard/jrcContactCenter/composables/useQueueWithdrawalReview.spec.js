import { afterEach, describe, expect, it } from 'vitest';
import { defineComponent, h, nextTick, ref } from 'vue';
import { enableAutoUnmount, mount } from '@vue/test-utils';
import { useQueueWithdrawalReview } from './useQueueWithdrawalReview';

enableAutoUnmount(afterEach);
const parameters = () => ({
  accountId: ref('1'),
  resource: ref('memberships'),
  record: ref({ id: '2', queue_id: '3' }),
  draft: ref({ active: false, priority: 10 }),
  allowed: ref(true),
});
const reply = (changes = {}) => ({
  response: {
    data: {
      error: 'last_eligible_confirmation_required',
      review: {
        account_id: '1',
        membership_id: '2',
        queue_id: '3',
        queue_name: 'SYNTHETIC queue',
        previous_count: 1,
        remaining_count: 0,
        review_token: 'synthetic-client-only-receipt',
        ...changes,
      },
    },
  },
});
const render = params =>
  mount(
    defineComponent({
      setup: () => useQueueWithdrawalReview(params),
      render: () => h('div'),
    })
  );

describe('manager review of the last configured eligible agent', () => {
  it('blocks retry until the manager explicitly confirms the bound impact', () => {
    const wrapper = render(parameters());
    expect(wrapper.vm.handleError(reply())).toBe(true);
    expect(wrapper.vm.canSave).toBe(false);
    expect(wrapper.vm.options()).toEqual({});
    wrapper.vm.state.confirmed = true;
    expect(wrapper.vm.canSave).toBe(true);
    expect(wrapper.vm.options()).toEqual({
      manager_confirmation: {
        confirmed: true,
        review_token: 'synthetic-client-only-receipt',
      },
    });
  });

  it('invalidates a confirmed receipt after any draft change instead of silently reusing it', async () => {
    const params = parameters();
    const wrapper = render(params);
    wrapper.vm.handleError(reply());
    wrapper.vm.state.confirmed = true;
    params.draft.value.priority = 11;
    await nextTick();
    expect(wrapper.vm.state.review).toBeNull();
    expect(wrapper.vm.state.confirmed).toBe(false);
    expect(wrapper.vm.options()).toEqual({});
  });

  it.each(['accountId', 'resource', 'record', 'allowed'])(
    'clears sensitive review state after %s changes',
    async key => {
      const params = parameters();
      const wrapper = render(params);
      wrapper.vm.handleError(reply());
      wrapper.vm.state.confirmed = true;
      if (key === 'record') params.record.value = { id: '9', queue_id: '3' };
      else if (key === 'allowed') params.allowed.value = false;
      else params[key].value = 'different-context';
      await nextTick();
      expect(wrapper.vm.state.review).toBeNull();
      expect(wrapper.vm.options()).toEqual({});
    }
  );

  it.each([
    { account_id: '99' },
    { membership_id: '99' },
    { queue_id: '99' },
    { previous_count: 0 },
    { remaining_count: 1 },
    { review_token: '' },
  ])('rejects a mismatched or incomplete impact %j', changes => {
    const wrapper = render(parameters());
    expect(wrapper.vm.handleError(reply(changes))).toBe(true);
    expect(wrapper.vm.state.error).toBe(true);
    expect(wrapper.vm.canSave).toBe(false);
    expect(wrapper.vm.options()).toEqual({});
  });

  it('leaves unrelated errors to the native configuration revision/error handlers', () => {
    const wrapper = render(parameters());
    expect(
      wrapper.vm.handleError({
        response: { data: { error: 'stale_configuration_revision' } },
      })
    ).toBe(false);
    expect(wrapper.vm.state.review).toBeNull();
  });
});
