import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import CampaignApproval from '../components/CampaignApproval.vue';
import api from 'dashboard/api/jrcCampaigns';
import { useAlert } from 'dashboard/composables';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: { requestReview: vi.fn(), approve: vi.fn() },
}));
enableAutoUnmount(afterEach);

const campaign = {
  id: 17,
  name: 'Synthetic campaign',
  review_digest: 'review-a',
  delay_min_seconds: 60,
  delay_max_seconds: 60,
  sending_window: { days: [1], start: '08:00', end: '18:00' },
  campaign_inboxes: [],
  steps: [],
  review_snapshot: { configuration: {}, recipients: [] },
};

describe('campaign approval pending requests', () => {
  beforeEach(() => {
    api.requestReview.mockResolvedValue({ data: campaign });
    api.approve.mockResolvedValue({ data: {} });
  });

  it('does not apply a pending review from a previously selected campaign', async () => {
    let resolveOld;
    api.requestReview.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = mount(CampaignApproval, { props: { campaign } });
    const current = {
      ...campaign,
      id: 18,
      name: 'Current campaign',
      review_digest: 'review-b',
    };
    api.requestReview.mockResolvedValueOnce({ data: current });
    await wrapper.setProps({ campaign: current });
    await flushPromises();
    resolveOld({ data: campaign });
    await flushPromises();
    expect(api.requestReview).toHaveBeenLastCalledWith(18);
    expect(wrapper.vm.review.id).toBe(18);
    expect(wrapper.vm.accepted).toBe(false);
  });

  it('admits one approval mutation while the first approval is pending', async () => {
    const wrapper = mount(CampaignApproval, { props: { campaign } });
    await flushPromises();
    await wrapper.get('input[type="checkbox"]').setValue(true);
    let resolveApproval;
    api.approve.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveApproval = resolve;
        })
    );
    const first = wrapper.vm.approve();
    const duplicate = wrapper.vm.approve();
    expect(api.approve).toHaveBeenCalledExactlyOnceWith(17, 'review-a');
    resolveApproval({ data: {} });
    await Promise.all([first, duplicate]);
    expect(wrapper.emitted('approved')).toHaveLength(1);
  });

  it('does not emit approval or an alert after the dialog has closed', async () => {
    const wrapper = mount(CampaignApproval, { props: { campaign } });
    await flushPromises();
    await wrapper.get('input[type="checkbox"]').setValue(true);
    let resolveApproval;
    api.approve.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveApproval = resolve;
        })
    );
    const pending = wrapper.vm.approve();
    wrapper.unmount();
    resolveApproval({ data: {} });
    await pending;
    expect(wrapper.emitted('approved')).toBeUndefined();
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('does not repeat a completed approval before its parent disposes the dialog', async () => {
    const wrapper = mount(CampaignApproval, { props: { campaign } });
    await flushPromises();
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper.vm.approve();
    await wrapper.vm.approve();
    expect(api.approve).toHaveBeenCalledExactlyOnceWith(17, 'review-a');
    expect(wrapper.emitted('approved')).toHaveLength(1);
  });

  it('keeps a new campaign review while an older approval finishes without signaling approval for the new campaign', async () => {
    const wrapper = mount(CampaignApproval, { props: { campaign } });
    await flushPromises();
    await wrapper.get('input[type="checkbox"]').setValue(true);
    let resolveApproval;
    api.approve.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveApproval = resolve;
        })
    );
    const pending = wrapper.vm.approve();
    const current = { ...campaign, id: 18, review_digest: 'review-b' };
    api.requestReview.mockResolvedValueOnce({ data: current });
    await wrapper.setProps({ campaign: current });
    await flushPromises();
    expect(wrapper.vm.saving).toBe(true);
    resolveApproval({ data: {} });
    await pending;
    expect(wrapper.vm.review.id).toBe(18);
    expect(wrapper.vm.saving).toBe(false);
    expect(wrapper.emitted('approved')).toBeUndefined();
    expect(useAlert).not.toHaveBeenCalled();
  });
});
