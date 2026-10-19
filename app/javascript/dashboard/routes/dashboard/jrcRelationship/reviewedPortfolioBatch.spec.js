import { mount, flushPromises } from '@vue/test-utils';
import { beforeEach, afterEach, expect, it, vi } from 'vitest';
import ReviewedPortfolioBatchPanel from './ReviewedPortfolioBatchPanel.vue';
const api = vi.hoisted(() => ({
  previewPortfolioBatch: vi.fn(),
  portfolioBatchReview: vi.fn(),
  approvePortfolioBatch: vi.fn(),
  advancePortfolioBatch: vi.fn(),
  cancelPortfolioBatch: vi.fn(),
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
beforeEach(() => {
  vi.clearAllMocks();
  sessionStorage.clear();
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
