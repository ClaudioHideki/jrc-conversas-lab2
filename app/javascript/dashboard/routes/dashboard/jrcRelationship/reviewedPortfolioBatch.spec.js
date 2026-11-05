import { mount, flushPromises } from '@vue/test-utils';
import { beforeEach, afterEach, expect, it, vi } from 'vitest';
import ReviewedPortfolioBatchPanel from './ReviewedPortfolioBatchPanel.vue';
const api = vi.hoisted(() => ({
  previewPortfolioBatch: vi.fn(),
  portfolioBatchReview: vi.fn(),
  approvePortfolioBatch: vi.fn(),
  advancePortfolioBatch: vi.fn(),
  cancelPortfolioBatch: vi.fn(),
  requestPortfolioBatchApproval: vi.fn(),
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: api }));
const proposal = {
  ids: [19],
  operation: 'assign',
  owner_id: null,
  request_id: 'synthetic-request',
};
const review = {
  id: 5,
  digest: 'a'.repeat(64),
  revision: 1,
  state: 'previewed',
  expires_at: '2026-10-19T17:00:00Z',
  inputs: proposal,
  items: [
    {
      assignment_id: 19,
      label: 'Synthetic customer',
      state: 'pending',
      receipt: null,
      error_code: null,
    },
  ],
};
let wrapper;
it.each(['blocked', 'stale', 'unavailable', 'failed'])(
  'prevents confirmation and approval requests for %s responsibilities',
  async state => {
    api.previewPortfolioBatch.mockResolvedValueOnce({
      data: {
        ...review,
        responsibilities: [
          { assignment_id: 19, entries: [], blockers: [], state },
        ],
        approval: { required: true, state: 'required', requests: [] },
      },
    });
    wrapper = mount(ReviewedPortfolioBatchPanel, {
      props: { accountId: '12', proposal },
    });
    await flushPromises();
    expect(
      wrapper.get('[data-test="review-request-approval"]').element.disabled
    ).toBe(true);
    expect(wrapper.get('[data-test="review-approve"]').element.disabled).toBe(
      true
    );
    expect(api.requestPortfolioBatchApproval).not.toHaveBeenCalled();
    expect(api.approvePortfolioBatch).not.toHaveBeenCalled();
  }
);
beforeEach(() => {
  vi.clearAllMocks();
  sessionStorage.clear();
  api.requestPortfolioBatchApproval.mockResolvedValue({
    data: {
      ...review,
      approval: { required: true, state: 'required', requests: [] },
    },
  });
  api.previewPortfolioBatch.mockResolvedValue({ data: review });
  api.portfolioBatchReview.mockResolvedValue({ data: review });
  api.approvePortfolioBatch.mockResolvedValue({
    data: { ...review, state: 'running', revision: 2 },
  });
  api.advancePortfolioBatch.mockResolvedValue({
    data: {
      ...review,
      state: 'completed',
      revision: 3,
      items: [
        { ...review.items[0], state: 'applied', receipt: { updated: 1 } },
      ],
    },
  });
  api.cancelPortfolioBatch.mockResolvedValue({
    data: { ...review, state: 'canceled', revision: 3 },
  });
});
afterEach(() => {
  wrapper?.unmount();
});
it('blocks over-capacity execution and clears captured workload after an authorization change', async () => {
  api.previewPortfolioBatch.mockResolvedValueOnce({
    data: {
      ...review,
      capacity: [{ scope_key: 'account', blocker: 'capacity_exceeded' }],
    },
  });
  wrapper = mount(ReviewedPortfolioBatchPanel, {
    props: { accountId: '12', proposal, authorizationKey: 'initial' },
  });
  await flushPromises();
  expect(wrapper.get('[data-test="review-approve"]').element.disabled).toBe(
    true
  );
  await wrapper.get('[data-test="review-approve"]').trigger('click');
  expect(api.approvePortfolioBatch).not.toHaveBeenCalled();
  await wrapper.setProps({ authorizationKey: 'revoked' });
  expect(wrapper.find('[data-test="review-approve"]').exists()).toBe(false);
});
it('prepares only a preview and requires explicit confirmation bound to its account and digest', async () => {
  wrapper = mount(ReviewedPortfolioBatchPanel, {
    props: { accountId: '12', proposal },
  });
  await flushPromises();
  expect(api.previewPortfolioBatch).toHaveBeenCalledWith(
    '12',
    proposal,
    expect.any(Object)
  );
  expect(api.approvePortfolioBatch).not.toHaveBeenCalled();
  expect(wrapper.text()).toContain('Synthetic customer');
  await wrapper.get('[data-test="review-approve"]').trigger('click');
  await flushPromises();
  expect(api.approvePortfolioBatch).toHaveBeenCalledWith(
    '12',
    5,
    review.digest,
    expect.any(Object)
  );
  await wrapper.get('[data-test="review-advance"]').trigger('click');
  await flushPromises();
  expect(wrapper.find('[data-test="review-approve"]').exists()).toBe(false);
  expect(wrapper.emitted('updated')).toBeTruthy();
});
it('discards a late preview after an account change and never approves its former audience', async () => {
  let release;
  api.previewPortfolioBatch.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        release = resolve;
      })
  );
  wrapper = mount(ReviewedPortfolioBatchPanel, {
    props: { accountId: '12', proposal },
  });
  await wrapper.setProps({ accountId: '13' });
  release({ data: review });
  await flushPromises();
  expect(wrapper.text()).not.toContain('Synthetic customer');
  expect(wrapper.find('[data-test="review-approve"]').exists()).toBe(false);
  expect(api.previewPortfolioBatch).toHaveBeenCalledTimes(1);
});
it('cancels without replaying approval and keeps the terminal review after a late read', async () => {
  let release;
  api.portfolioBatchReview.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        release = resolve;
      })
  );
  wrapper = mount(ReviewedPortfolioBatchPanel, {
    props: { accountId: '12', proposal },
  });
  await flushPromises();
  await wrapper.get('[data-test="review-refresh"]').trigger('click');
  await wrapper.get('[data-test="review-cancel"]').trigger('click');
  await flushPromises();
  release({ data: review });
  await flushPromises();
  expect(api.cancelPortfolioBatch).toHaveBeenCalledWith(
    '12',
    5,
    expect.any(Object)
  );
  expect(wrapper.find('[data-test="review-approve"]').exists()).toBe(false);
  expect(api.approvePortfolioBatch).not.toHaveBeenCalled();
});
it('removes an unapproved preview when its selection is edited', async () => {
  wrapper = mount(ReviewedPortfolioBatchPanel, {
    props: { accountId: '12', proposal },
  });
  await flushPromises();
  expect(wrapper.find('[data-test="review-approve"]').exists()).toBe(true);
  await wrapper.setProps({ proposal: null });
  await flushPromises();
  expect(wrapper.find('[data-test="review-approve"]').exists()).toBe(false);
  expect(api.approvePortfolioBatch).not.toHaveBeenCalled();
});
it('recovers only the account and operator saved operation without approving it again', async () => {
  sessionStorage.setItem('relationship-reviewed-batch:12:7', '5');
  wrapper = mount(ReviewedPortfolioBatchPanel, {
    props: { accountId: '12', actorId: 7 },
  });
  await flushPromises();
  expect(api.portfolioBatchReview).toHaveBeenCalledWith(
    '12',
    5,
    expect.any(Object)
  );
  expect(api.approvePortfolioBatch).not.toHaveBeenCalled();
  expect(wrapper.text()).toContain('Synthetic customer');
});

it('requires a formal native vote instead of enabling execution after manual preview', async () => {
  api.previewPortfolioBatch.mockResolvedValue({
    data: {
      ...review,
      approval: { required: true, state: 'required', requests: [] },
    },
  });
  wrapper = mount(ReviewedPortfolioBatchPanel, {
    props: { accountId: '12', proposal },
  });
  await flushPromises();
  expect(wrapper.get('[data-test="review-approve"]').element.disabled).toBe(
    true
  );
  await wrapper.get('[data-test="review-request-approval"]').trigger('click');
  await flushPromises();
  expect(api.requestPortfolioBatchApproval).toHaveBeenCalledWith(
    '12',
    5,
    { digest: review.digest, idempotency_key: expect.any(String) },
    expect.any(Object)
  );
  expect(api.approvePortfolioBatch).not.toHaveBeenCalled();
});
it('requires a separate execution confirmation after native approval', async () => {
  api.previewPortfolioBatch.mockResolvedValue({
    data: {
      ...review,
      approval: { required: true, state: 'approved', requests: [] },
    },
  });
  wrapper = mount(ReviewedPortfolioBatchPanel, {
    props: { accountId: '12', proposal },
  });
  await flushPromises();
  expect(wrapper.get('[data-test="review-approve"]').element.disabled).toBe(
    true
  );
  await wrapper
    .get('[data-test="review-execution-confirmation"]')
    .setValue(true);
  await wrapper.get('[data-test="review-approve"]').trigger('click');
  await flushPromises();
  expect(api.approvePortfolioBatch).toHaveBeenCalledTimes(1);
});
it('retains the same native approval intent after a failed request instead of creating duplicates', async () => {
  const data = {
    ...review,
    approval: { required: true, state: 'required', requests: [] },
  };
  api.previewPortfolioBatch.mockResolvedValue({ data });
  api.portfolioBatchReview.mockResolvedValue({ data });
  api.requestPortfolioBatchApproval.mockRejectedValueOnce(
    new Error('local interruption')
  );
  wrapper = mount(ReviewedPortfolioBatchPanel, {
    props: { accountId: '12', proposal },
  });
  await flushPromises();
  await wrapper.get('[data-test="review-request-approval"]').trigger('click');
  await flushPromises();
  await wrapper.get('[data-test="review-refresh"]').trigger('click');
  await flushPromises();
  await wrapper.get('[data-test="review-request-approval"]').trigger('click');
  await flushPromises();
  expect(api.requestPortfolioBatchApproval.mock.calls[0][2]).toEqual(
    api.requestPortfolioBatchApproval.mock.calls[1][2]
  );
  expect(api.approvePortfolioBatch).not.toHaveBeenCalled();
});
it('invalidates the execution checkbox when native approval evidence changes on refresh', async () => {
  api.previewPortfolioBatch.mockResolvedValue({
    data: {
      ...review,
      approval: { required: true, state: 'approved', requests: [] },
    },
  });
  wrapper = mount(ReviewedPortfolioBatchPanel, {
    props: { accountId: '12', proposal },
  });
  await flushPromises();
  await wrapper
    .get('[data-test="review-execution-confirmation"]')
    .setValue(true);
  api.portfolioBatchReview.mockResolvedValue({
    data: {
      ...review,
      approval: { required: true, state: 'stale', requests: [] },
    },
  });
  await wrapper.get('[data-test="review-refresh"]').trigger('click');
  await flushPromises();
  expect(wrapper.get('[data-test="review-approve"]').element.disabled).toBe(
    true
  );
  expect(api.approvePortfolioBatch).not.toHaveBeenCalled();
});

it('creates a new intent when a refreshed selected policy version requires a new formal decision', async () => {
  api.previewPortfolioBatch.mockResolvedValue({
    data: {
      ...review,
      approval: {
        required: true,
        state: 'required',
        requests: [],
        policy_version_ids: [1],
      },
    },
  });
  wrapper = mount(ReviewedPortfolioBatchPanel, {
    props: { accountId: '12', proposal },
  });
  await flushPromises();
  await wrapper.get('[data-test="review-request-approval"]').trigger('click');
  await flushPromises();
  api.portfolioBatchReview.mockResolvedValue({
    data: {
      ...review,
      approval: {
        required: true,
        state: 'required',
        requests: [{ id: 8, state: 'approved', policy_version_id: 1 }],
        policy_version_ids: [2],
      },
    },
  });
  await wrapper.get('[data-test="review-refresh"]').trigger('click');
  await flushPromises();
  await wrapper.get('[data-test="review-request-approval"]').trigger('click');
  await flushPromises();
  expect(
    api.requestPortfolioBatchApproval.mock.calls[0][2].idempotency_key
  ).not.toBe(
    api.requestPortfolioBatchApproval.mock.calls[1][2].idempotency_key
  );
  expect(api.approvePortfolioBatch).not.toHaveBeenCalled();
});
it('opens an existing current pending approval instead of admitting another request', async () => {
  api.previewPortfolioBatch.mockResolvedValue({
    data: {
      ...review,
      approval: {
        required: true,
        state: 'required',
        requests: [{ id: 8, state: 'pending', policy_version_id: 1 }],
        policy_version_ids: [1],
      },
    },
  });
  wrapper = mount(ReviewedPortfolioBatchPanel, {
    props: { accountId: '12', proposal },
  });
  await flushPromises();
  expect(wrapper.find('[data-test="review-request-approval"]').exists()).toBe(
    false
  );
  expect(wrapper.get('[data-test="review-approve"]').element.disabled).toBe(
    true
  );
  expect(api.requestPortfolioBatchApproval).not.toHaveBeenCalled();
});
