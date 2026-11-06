import { mount, shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import messages from 'dashboard/i18n/locale/en/relationship.json';
import NativePanel from './ReviewedPortfolioBatchPanel.vue';
import Membership from './PortfolioMembershipBatchPanel.vue';
import Groups from './PortfolioGroupsPanel.vue';
import Customers from './PortfolioGroupCustomersDialog.vue';
import { validMembershipReview } from './portfolioMembershipReviewReceipt';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  router: { push: vi.fn() },
  api: {
    previewPortfolioBatch: vi.fn(),
    portfolioBatchReview: vi.fn(),
    approvePortfolioBatch: vi.fn(),
    advancePortfolioBatch: vi.fn(),
    cancelPortfolioBatch: vi.fn(),
    portfolioGroup: vi.fn(),
    portfolioGroupCustomers: vi.fn(),
    savePortfolioGroupCustomers: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => mocks.router,
}));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));
const proposal = {
  operation: 'portfolio_membership',
  ids: [31, 32],
  portfolio_group_id: 18,
  expected_version: 0,
  active: true,
  justification: 'Explicit scoped customer review',
  request_id: 'b6617842-8401-44bf-a34a-8f1f90b623e6',
};
const group = {
  id: 18,
  version: 0,
  name: 'Synthetic current portfolio',
  status: 'active',
  can_manage: true,
};
const preview = {
  id: 91,
  revision: 1,
  digest: 'a'.repeat(64),
  state: 'previewed',
  inputs: proposal,
  summary: {
    portfolio_group_id: 18,
    portfolio_group_name: group.name,
    active: true,
  },
  items: [31, 32].map(id => ({
    assignment_id: id,
    label: `Synthetic customer ${id}`,
    state: 'pending',
    receipt: null,
    error_code: null,
  })),
};
const completed = {
  ...preview,
  revision: 4,
  state: 'completed',
  items: preview.items.map((item, index) => ({
    ...item,
    state: 'applied',
    receipt: {
      updated: 1,
      operation: 'portfolio_membership',
      assignment_id: item.assignment_id,
      portfolio_group_id: 18,
      group_revision_before: index,
      group_version: 1,
      membership_state: index ? 'already_linked' : 'linked',
    },
  })),
};
const attention = {
  ...preview,
  revision: 4,
  state: 'attention',
  items: [
    completed.items[0],
    {
      ...preview.items[1],
      state: 'failed',
      error_code: 'BATCH_NATIVE_OPERATION_FAILED',
    },
  ],
};
const wrappers = [];
const render = (
  component = NativePanel,
  props = { accountId: '1400', actorId: 7, portfolioGroupId: 18, proposal },
  shallow = false
) => {
  const wrapper = (shallow ? shallowMount : mount)(component, {
    props,
    global: {
      stubs: {
        ReviewedCadencePanel: true,
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });
  wrappers.push(wrapper);
  return wrapper;
};
beforeEach(() => {
  vi.resetAllMocks();
  sessionStorage.clear();
  mocks.route = reactive({
    params: { accountId: '1400' },
    query: { group_id: '18' },
  });
  mocks.store = reactive({
    getters: {
      getCurrentUserID: 7,
      getCurrentRole: 'administrator',
      getCurrentUser: { accounts: [] },
    },
  });
  mocks.api.previewPortfolioBatch.mockResolvedValue({
    data: structuredClone(preview),
  });
  mocks.api.approvePortfolioBatch.mockResolvedValue({
    data: { ...structuredClone(preview), revision: 2, state: 'running' },
  });
  mocks.api.advancePortfolioBatch.mockResolvedValue({
    data: structuredClone(completed),
  });
  mocks.api.portfolioBatchReview.mockResolvedValue({
    data: structuredClone(completed),
  });
  mocks.api.portfolioGroup.mockResolvedValue({
    data: { ...group, version: 5 },
  });
  mocks.api.portfolioGroupCustomers.mockResolvedValue({
    data: { payload: [], meta: { page: 1, per_page: 25, total: 0 } },
  });
});
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

it('prepares without writes and requires explicit confirmation before showing validated native per-item receipts', async () => {
  const wrapper = render();
  await flushPromises();
  expect(mocks.api.approvePortfolioBatch).not.toHaveBeenCalled();
  expect(mocks.api.advancePortfolioBatch).not.toHaveBeenCalled();
  await wrapper.get('[data-test="review-approve"]').trigger('click');
  await flushPromises();
  expect(mocks.api.approvePortfolioBatch).toHaveBeenCalledWith(
    '1400',
    91,
    preview.digest,
    expect.objectContaining({ signal: expect.any(AbortSignal) })
  );
  await wrapper.get('[data-test="review-advance"]').trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain(
    messages.RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.STATES.linked
  );
  expect(wrapper.text()).toContain(
    messages.RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.STATES.already_linked
  );
  expect(wrapper.emitted('updated')).toHaveLength(1);
});

it('rejects a successful HTTP response for another group before storing or exposing its review', async () => {
  mocks.api.previewPortfolioBatch.mockResolvedValue({
    data: { ...preview, inputs: { ...proposal, portfolio_group_id: 19 } },
  });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toBe(
    messages.RELATIONSHIP.NAMED_PORTFOLIOS.BATCH.UNCONFIRMED
  );
  expect(wrapper.find('[data-test="review-approve"]').exists()).toBe(false);
  expect(
    sessionStorage.getItem('relationship-reviewed-batch:1400:7:portfolio:18')
  ).toBeNull();
  expect(wrapper.emitted('reviewed')).toBeUndefined();
});

it('does not claim completion from malformed receipts and recovers by the exact original preview identity without repeating effects', async () => {
  const invalid = structuredClone(completed);
  invalid.items[1].receipt.group_version = 90;
  mocks.api.advancePortfolioBatch.mockResolvedValue({ data: invalid });
  const wrapper = render();
  await flushPromises();
  await wrapper.get('[data-test="review-approve"]').trigger('click');
  await flushPromises();
  await wrapper.get('[data-test="review-advance"]').trigger('click');
  await flushPromises();
  expect(wrapper.emitted('updated')).toBeUndefined();
  expect(wrapper.find('[data-test="review-advance"]').exists()).toBe(false);
  expect(wrapper.text()).not.toContain(
    messages.RELATIONSHIP.REVIEWED_BATCH.STATES.completed
  );
  mocks.api.previewPortfolioBatch.mockResolvedValue({ data: completed });
  await wrapper.get('[data-test="review-refresh"]').trigger('click');
  await flushPromises();
  expect(mocks.api.previewPortfolioBatch).toHaveBeenLastCalledWith(
    '1400',
    proposal,
    expect.any(Object)
  );
  expect(mocks.api.advancePortfolioBatch).toHaveBeenCalledOnce();
  expect(wrapper.text()).toContain(
    messages.RELATIONSHIP.REVIEWED_BATCH.STATES.completed
  );
});

it('recovers only the scoped group session pointer while preserving the existing ordinary review pointer', async () => {
  sessionStorage.setItem('relationship-reviewed-batch:1400:7', '56');
  sessionStorage.setItem(
    'relationship-reviewed-batch:1400:7:portfolio:18',
    '91'
  );
  const wrapper = render(NativePanel, {
    accountId: '1400',
    actorId: 7,
    portfolioGroupId: 18,
  });
  await flushPromises();
  expect(mocks.api.portfolioBatchReview).toHaveBeenCalledWith(
    '1400',
    91,
    expect.any(Object)
  );
  expect(sessionStorage.getItem('relationship-reviewed-batch:1400:7')).toBe(
    '56'
  );
  expect(wrapper.text()).toContain(group.name);
  await wrapper.setProps({ portfolioGroupId: 19 });
  expect(wrapper.text()).not.toContain(group.name);
});

it('retries unknown preview outcomes with the same UUID and never restages old selection after authority changes', async () => {
  mocks.api.previewPortfolioBatch.mockRejectedValueOnce(
    new Error('Synthetic unknown response')
  );
  const wrapper = render();
  await flushPromises();
  await wrapper.get('[data-test="review-refresh"]').trigger('click');
  await flushPromises();
  expect(mocks.api.previewPortfolioBatch).toHaveBeenLastCalledWith(
    '1400',
    proposal,
    expect.any(Object)
  );
  await wrapper.setProps({ authorizationKey: 'new native role context' });
  sessionStorage.removeItem('relationship-reviewed-batch:1400:7:portfolio:18');
  await wrapper.get('[data-test="review-refresh"]').trigger('click');
  await flushPromises();
  expect(mocks.api.previewPortfolioBatch).toHaveBeenCalledTimes(2);
});

it('rejects wrong audience, null items, incomplete terminal receipts and mismatched request identity', () => {
  expect(validMembershipReview(preview, 18, proposal)).toBe(true);
  expect(validMembershipReview(completed, 18, proposal)).toBe(true);
  expect(
    validMembershipReview({ ...preview, items: [null, preview.items[1]] }, 18)
  ).toBe(false);
  expect(
    validMembershipReview(
      { ...preview, inputs: { ...proposal, ids: [31, 33] } },
      18
    )
  ).toBe(false);
  expect(validMembershipReview({ ...preview, state: 'completed' }, 18)).toBe(
    false
  );
  expect(
    validMembershipReview(preview, 18, { ...proposal, request_id: 'different' })
  ).toBe(false);
});

it('re-reviews only unresolved items with a fresh group revision and new explicit reason, preserving the old terminal result', async () => {
  const original = structuredClone(attention);
  const wrapper = render(Membership, { group }, true);
  wrapper.findComponent(NativePanel).vm.$emit('reviewed', original);
  await flushPromises();
  await wrapper.get('textarea').setValue('  Fresh operational review  ');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.api.portfolioGroup).toHaveBeenCalledWith(
    '1400',
    18,
    expect.any(Object)
  );
  expect(wrapper.findComponent(NativePanel).props('proposal')).toEqual(
    expect.objectContaining({
      ids: [32],
      expected_version: 5,
      previous_review_id: 91,
      active: true,
      justification: 'Fresh operational review',
    })
  );
  expect(wrapper.emitted('proposal')).toHaveLength(1);
  expect(original).toEqual(attention);
});

it('aborts a late fresh-group read when membership changes and cannot repopulate the old proposal', async () => {
  let resolve;
  mocks.api.portfolioGroup.mockReturnValueOnce(
    new Promise(done => {
      resolve = done;
    })
  );
  const wrapper = render(Membership, { group }, true);
  wrapper.findComponent(NativePanel).vm.$emit('reviewed', attention);
  await flushPromises();
  await wrapper.get('textarea').setValue('Fresh reason');
  await wrapper.get('form').trigger('submit');
  const signal = mocks.api.portfolioGroup.mock.calls[0][2].signal;
  mocks.store.getters.getCurrentUser.accounts = [
    { id: 1400, custom_role_id: 22 },
  ];
  await flushPromises();
  resolve({ data: { ...group, version: 5 } });
  await flushPromises();
  expect(signal.aborted).toBe(true);
  expect(wrapper.emitted('proposal')).toBeUndefined();
  expect(wrapper.findComponent(NativePanel).props('proposal')).toBeNull();
});

it('allows a fresh explicit review after a rejected preview but does not invent a prior persisted review ID', async () => {
  const wrapper = render(Membership, { group, proposal }, true);
  wrapper.findComponent(NativePanel).vm.$emit('previewFailed', 422);
  await flushPromises();
  await wrapper
    .get('textarea')
    .setValue('Review this selection against current group data');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  const next = wrapper.findComponent(NativePanel).props('proposal');
  expect(next.ids).toEqual([31, 32]);
  expect(next.expected_version).toBe(5);
  expect(next).not.toHaveProperty('previous_review_id');
  expect(next.request_id).not.toBe(proposal.request_id);
});

it.each([401, 403, 404])(
  'clears batch controls after an observed native access denial %s',
  async status => {
    const wrapper = render(Membership, { group, proposal }, true);
    wrapper.findComponent(NativePanel).vm.$emit('previewFailed', status);
    await flushPromises();
    expect(wrapper.findComponent(NativePanel).exists()).toBe(false);
    expect(wrapper.find('form').exists()).toBe(false);
  }
);

it('prepares the group batch from the existing review dialog without invoking the atomic writer and retains new re-review identity across tabs', async () => {
  const wrapper = render(
    Groups,
    { metadata: { can_manage: true, can_team: true } },
    true
  );
  await flushPromises();
  const add = wrapper
    .findAll('button')
    .find(
      row => row.text() === messages.RELATIONSHIP.NAMED_PORTFOLIOS.ADD_CUSTOMERS
    );
  await add.trigger('click');
  wrapper.findComponent(Customers).vm.$emit('batch', {
    assignment_ids: [31, 32],
    expected_version: 5,
    active: true,
    reason: 'Explicit named group reason',
  });
  await flushPromises();
  expect(wrapper.findComponent(Membership).props('proposal')).toEqual(
    expect.objectContaining({
      operation: 'portfolio_membership',
      ids: [31, 32],
      portfolio_group_id: 18,
      expected_version: 5,
      active: true,
    })
  );
  expect(mocks.api.savePortfolioGroupCustomers).not.toHaveBeenCalled();
  const next = {
    ...proposal,
    request_id: 'bca146b9-abba-435b-9305-72cbe60f41d6',
  };
  wrapper.findComponent(Membership).vm.$emit('proposal', next);
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(
      row => row.text() === messages.RELATIONSHIP.NAMED_PORTFOLIOS.CUSTOMERS
    )
    .trigger('click');
  await wrapper
    .findAll('button')
    .find(
      row => row.text() === messages.RELATIONSHIP.NAMED_PORTFOLIOS.BATCH.TITLE
    )
    .trigger('click');
  expect(wrapper.findComponent(Membership).props('proposal').request_id).toBe(
    next.request_id
  );
});

it('removes already visible customer data after a native read denial and cannot confirm the old review', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('Synthetic customer 31');
  mocks.api.portfolioBatchReview.mockRejectedValueOnce({
    response: { status: 403, data: { error: 'Native scope denied' } },
  });
  await wrapper.get('[data-test="review-refresh"]').trigger('click');
  await flushPromises();
  expect(wrapper.text()).not.toContain('Synthetic customer 31');
  expect(wrapper.find('[data-test="review-approve"]').exists()).toBe(false);
  expect(wrapper.emitted('accessDenied')).toEqual([[403]]);
});

it('blocks execution from a readonly group while retaining native cancellation of pending work', async () => {
  const cancelled = {
    ...preview,
    revision: 2,
    state: 'canceled',
    items: preview.items.map(item => ({ ...item, state: 'canceled' })),
  };
  mocks.api.cancelPortfolioBatch.mockResolvedValue({ data: cancelled });
  const wrapper = render(NativePanel, {
    accountId: '1400',
    actorId: 7,
    portfolioGroupId: 18,
    proposal,
    canExecute: false,
  });
  await flushPromises();
  expect(
    wrapper.get('[data-test="review-approve"]').attributes('disabled')
  ).toBeDefined();
  await wrapper.get('[data-test="review-approve"]').trigger('click');
  expect(mocks.api.approvePortfolioBatch).not.toHaveBeenCalled();
  await wrapper.get('[data-test="review-cancel"]').trigger('click');
  await flushPromises();
  expect(mocks.api.cancelPortfolioBatch).toHaveBeenCalledWith(
    '1400',
    91,
    expect.any(Object)
  );
  expect(wrapper.text()).toContain(
    messages.RELATIONSHIP.REVIEWED_BATCH.STATES.canceled
  );
});
