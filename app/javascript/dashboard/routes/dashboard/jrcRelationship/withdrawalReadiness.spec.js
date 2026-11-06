import { flushPromises, mount } from '@vue/test-utils';
import { defineComponent, reactive } from 'vue';
import Panel from './WithdrawalReadinessDialog.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  getters: null,
  request: vi.fn(),
  withdraw: vi.fn(),
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcRelationship', () => ({
  default: {
    withdrawalReadiness: mocks.request,
    withdrawAnalyst: mocks.withdraw,
  },
}));
const Dialog = defineComponent({
  setup(_, { expose }) {
    expose({ open: vi.fn() });
  },
  template: '<section><slot /></section>',
});
const render = () =>
  mount(Panel, { props: { analystId: 7 }, global: { stubs: { Dialog } } });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: 1 } });
  mocks.getters = reactive({
    getCurrentUser: { id: 3 },
    getCurrentRole: 'administrator',
  });
  mocks.request.mockResolvedValue({
    data: {
      state: 'pending_responsibilities',
      counts: { allocations: 0, actions: 1 },
      final_removal_available: false,
    },
  });
});

it('shows actual pending counts without offering a removal or automatic mutation action', async () => {
  const wrapper = render();
  await flushPromises();
  expect(mocks.request).toHaveBeenCalledWith(1, 7, expect.any(Object));
  expect(wrapper.text()).toContain(
    'RELATIONSHIP.WITHDRAWAL.pending_responsibilities'
  );
  expect(wrapper.text()).toContain('RELATIONSHIP.WITHDRAWAL.FINAL_REVIEW');
  expect(wrapper.findAll('button')).toHaveLength(0);
  expect(wrapper.findAll('dd').map(node => node.text())).toEqual(['0', '1']);
  wrapper.unmount();
});

it('reports missing visibility as unavailable without rendering fabricated zero counts', async () => {
  mocks.request.mockRejectedValue({ response: { status: 403 } });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toBe(
    'RELATIONSHIP.WITHDRAWAL.UNAVAILABLE'
  );
  expect(wrapper.findAll('dd')).toHaveLength(0);
  wrapper.unmount();
});

it('clears old account data and ignores a late response after an identity change', async () => {
  let finish;
  mocks.request.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render();
  mocks.route.params.accountId = 2;
  await flushPromises();
  finish({
    data: { state: 'ready_for_final_review', counts: { allocations: 999 } },
  });
  await flushPromises();
  expect(wrapper.emitted('close')).toHaveLength(1);
  expect(wrapper.text()).not.toContain('999');
  wrapper.unmount();
});

it('requires a current server authorization, reason and explicit scope confirmation before withdrawal', async () => {
  mocks.request.mockResolvedValueOnce({
    data: {
      state: 'ready_for_final_review',
      counts: { allocations: 0 },
      can_withdraw_relationship: true,
      snapshot_digest: 'a'.repeat(64),
    },
  });
  mocks.withdraw.mockResolvedValueOnce({
    data: { state: 'withdrawn', withdrawn_at: '2026-11-06T12:00:00Z' },
  });
  const wrapper = render();
  await flushPromises();
  const form = wrapper.get('[data-testid="withdrawal-confirmation"]');
  await form.trigger('submit');
  expect(mocks.withdraw).not.toHaveBeenCalled();
  await wrapper.get('textarea').setValue('Synthetic reviewed handover');
  await form.trigger('submit');
  expect(mocks.withdraw).not.toHaveBeenCalled();
  await wrapper.get('input[type="checkbox"]').setValue(true);
  await form.trigger('submit');
  await flushPromises();
  expect(mocks.withdraw).toHaveBeenCalledWith(
    1,
    7,
    {
      reason: 'Synthetic reviewed handover',
      snapshot_digest: 'a'.repeat(64),
    },
    expect.any(Object)
  );
  expect(wrapper.text()).toContain('RELATIONSHIP.WITHDRAWAL.WITHDRAWN');
  expect(wrapper.find('textarea').exists()).toBe(false);
  wrapper.unmount();
});

it('preserves the draft after a stale review, offers explicit refresh and never retries automatically', async () => {
  mocks.request.mockResolvedValueOnce({
    data: {
      state: 'ready_for_final_review',
      counts: {},
      can_withdraw_relationship: true,
      snapshot_digest: 'b'.repeat(64),
    },
  });
  mocks.withdraw.mockRejectedValueOnce({
    response: { status: 409, data: { errors: ['Refresh before retrying.'] } },
  });
  const wrapper = render();
  await flushPromises();
  await wrapper.get('textarea').setValue('Synthetic preserved reason');
  await wrapper.get('input[type="checkbox"]').setValue(true);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.get('textarea').element.value).toBe(
    'Synthetic preserved reason'
  );
  expect(wrapper.get('[role="alert"]').text()).toContain(
    'Refresh before retrying.'
  );
  expect(mocks.withdraw).toHaveBeenCalledTimes(1);
  expect(mocks.request).toHaveBeenCalledTimes(1);
  expect(wrapper.text()).not.toContain('RELATIONSHIP.WITHDRAWAL.WITHDRAWN');
  wrapper.unmount();
});

it('does not offer withdrawal from a legacy zero-count response without explicit current permission', async () => {
  mocks.request.mockResolvedValueOnce({
    data: { state: 'ready_for_final_review', counts: { allocations: 0 } },
  });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.find('form').exists()).toBe(false);
  expect(mocks.withdraw).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('prevents duplicate submission and ignores a late successful withdrawal after an account change', async () => {
  mocks.request.mockResolvedValueOnce({
    data: {
      state: 'ready_for_final_review',
      counts: {},
      can_withdraw_relationship: true,
      snapshot_digest: 'c'.repeat(64),
    },
  });
  let finish;
  mocks.withdraw.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render();
  await flushPromises();
  await wrapper.get('textarea').setValue('Synthetic in-flight reason');
  await wrapper.get('input[type="checkbox"]').setValue(true);
  await wrapper.get('form').trigger('submit');
  await wrapper.get('form').trigger('submit');
  expect(mocks.withdraw).toHaveBeenCalledTimes(1);
  expect(wrapper.get('textarea').attributes('disabled')).toBeDefined();
  mocks.route.params.accountId = 2;
  await flushPromises();
  finish({ data: { withdrawn_at: '2026-11-06T12:00:00Z' } });
  await flushPromises();
  expect(wrapper.emitted('close')).toHaveLength(1);
  expect(wrapper.text()).not.toContain('RELATIONSHIP.WITHDRAWAL.WITHDRAWN');
  wrapper.unmount();
});

it('clears protected review data when current permission is denied during submission', async () => {
  mocks.request.mockResolvedValueOnce({
    data: {
      state: 'ready_for_final_review',
      counts: { actions: 0 },
      can_withdraw_relationship: true,
      snapshot_digest: 'd'.repeat(64),
    },
  });
  mocks.withdraw.mockRejectedValueOnce({ response: { status: 403 } });
  const wrapper = render();
  await flushPromises();
  await wrapper.get('textarea').setValue('Synthetic changed permission');
  await wrapper.get('input[type="checkbox"]').setValue(true);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.emitted('close')).toHaveLength(1);
  expect(wrapper.findAll('dd')).toHaveLength(0);
  expect(wrapper.find('textarea').exists()).toBe(false);
  wrapper.unmount();
});
