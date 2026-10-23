import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import JrcCampaignsPage from '../JrcCampaignsPage.vue';
import api from 'dashboard/api/jrcCampaigns';
import { useAlert } from 'dashboard/composables';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: {
    get: vi.fn(),
    metadata: vi.fn(),
    analytics: vi.fn(),
    requestReview: vi.fn(),
    approve: vi.fn(),
    launch: vi.fn(),
  },
}));
enableAutoUnmount(afterEach);
const Wizard = {
  name: 'CampaignWizard',
  props: ['campaign', 'initialSanitizedListId'],
  emits: ['reviewRequested'],
  template: '<div data-wizard />',
};
const Lists = {
  name: 'SanitizedLists',
  emits: ['useList'],
  template: '<div data-lists />',
};
const campaign = {
  id: 17,
  name: 'QA campaign',
  status: 'draft',
  approval_valid: false,
  created_at: new Date().toISOString(),
  delivery_channel: 'whatsapp',
  delay_min_seconds: 60,
  delay_max_seconds: 60,
  sending_window: { days: [1], start: '08:00', end: '18:00' },
  campaign_inboxes: [],
  steps: [],
  review_digest: 'synthetic-digest',
  review_snapshot: {
    recipients: [{ name: 'QA', destination: '+5511999999000' }],
    configuration: {},
  },
};
const global = {
  stubs: {
    CampaignWizard: Wizard,
    SanitizedLists: Lists,
    CampaignPerformanceChart: true,
  },
  mocks: { $t: key => key },
};

describe('campaign page preserves the saved draft through review and launch', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.get.mockResolvedValue({ data: [] });
    api.metadata.mockResolvedValue({
      data: {
        labels: [],
        source_inboxes: [],
        whatsapp_inboxes: [],
        email_inboxes: [],
        pipelines: [],
        sanitized_lists: [],
      },
    });
    api.analytics.mockResolvedValue({
      data: {
        summary: {},
        previous_summary: {},
        series: [],
        failure_reasons: [],
      },
    });
    api.requestReview.mockResolvedValue({ data: campaign });
    api.approve.mockResolvedValue({
      data: { ...campaign, approval_valid: true },
    });
    api.launch.mockResolvedValue({ data: { ...campaign, status: 'running' } });
  });

  it('opens review for the same saved ID and sends a launch request only after approval and a separate Start click', async () => {
    const wrapper = mount(JrcCampaignsPage, { global });
    await flushPromises();
    expect(wrapper.text()).not.toMatch(/JARVIS|JEV/);
    expect(wrapper.text()).not.toContain('JRC_CAMPAIGNS.GOVERNANCE.CONSENTS');
    const create = wrapper
      .findAll('button')
      .find(button => button.text() === 'JRC_CAMPAIGNS.NEW_CAMPAIGN');
    await create.trigger('click');
    wrapper.getComponent(Wizard).vm.$emit('reviewRequested', campaign);
    await flushPromises();
    expect(wrapper.find('[data-wizard]').exists()).toBe(false);
    expect(api.requestReview).toHaveBeenCalledExactlyOnceWith(17);
    expect(api.launch).not.toHaveBeenCalled();
    const dialog = wrapper.get('[role="dialog"]');
    await dialog.get('input[type="checkbox"]').setValue(true);
    api.get.mockResolvedValue({
      data: [{ ...campaign, approval_valid: true }],
    });
    await dialog
      .findAll('button')
      .find(button => button.text() === 'JRC_CAMPAIGNS.GOVERNANCE.APPROVE')
      .trigger('click');
    await flushPromises();
    expect(api.approve).toHaveBeenCalledExactlyOnceWith(17, 'synthetic-digest');
    expect(api.launch).not.toHaveBeenCalled();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    await wrapper.get('button[title="JRC_CAMPAIGNS.START"]').trigger('click');
    await flushPromises();
    expect(api.launch).toHaveBeenCalledExactlyOnceWith(17);
  });

  it('opens a new campaign with the selected sanitized list instead of treating it as an existing campaign', async () => {
    const wrapper = mount(JrcCampaignsPage, { global });
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'JRC_CAMPAIGNS.TABS.SANITIZE')
      .trigger('click');
    wrapper.getComponent(Lists).vm.$emit('useList', { id: 7 });
    await flushPromises();
    expect(wrapper.getComponent(Wizard).props('initialSanitizedListId')).toBe(
      7
    );
    expect(wrapper.getComponent(Wizard).props('campaign')).toBe(null);
    expect(api.requestReview).not.toHaveBeenCalled();
    expect(api.launch).not.toHaveBeenCalled();
  });

  it('keeps a newer full refresh when an older campaign request completes later', async () => {
    const wrapper = mount(JrcCampaignsPage, { global });
    await flushPromises();
    let resolveOlder;
    api.get.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOlder = resolve;
        })
    );
    const older = wrapper.vm.fetchData();
    api.get.mockResolvedValueOnce({
      data: [{ ...campaign, id: 18, name: 'Latest' }],
    });
    await wrapper.vm.fetchData();
    resolveOlder({ data: [{ ...campaign, name: 'Obsolete' }] });
    await older;
    expect(wrapper.vm.campaigns.map(item => item.id)).toEqual([18]);
    expect(wrapper.text()).not.toContain('Obsolete');
  });

  it('does not finish the loading state while the latest full refresh is still pending', async () => {
    const wrapper = mount(JrcCampaignsPage, { global });
    await flushPromises();
    let resolveOlder;
    let resolveLatest;
    api.get
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            resolveOlder = resolve;
          })
      )
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            resolveLatest = resolve;
          })
      );
    const older = wrapper.vm.fetchData();
    const latest = wrapper.vm.fetchData();
    resolveOlder({ data: [] });
    await older;
    expect(wrapper.vm.loading).toBe(true);
    resolveLatest({ data: [] });
    await latest;
    expect(wrapper.vm.loading).toBe(false);
  });

  it('keeps a newer sender refresh when older metadata from a full refresh arrives later', async () => {
    const wrapper = mount(JrcCampaignsPage, { global });
    await flushPromises();
    let resolveOlder;
    api.metadata.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOlder = resolve;
        })
    );
    const older = wrapper.vm.fetchData();
    const latest = {
      ...wrapper.vm.metadata,
      whatsapp_inboxes: [{ id: 8, name: 'Latest sender' }],
    };
    api.metadata.mockResolvedValueOnce({ data: latest });
    await wrapper.vm.refreshSenders();
    resolveOlder({ data: { ...latest, whatsapp_inboxes: [] } });
    await older;
    expect(wrapper.vm.metadata.whatsapp_inboxes).toEqual(
      latest.whatsapp_inboxes
    );
  });

  it('keeps analytics for the latest filter when an older filter finishes later', async () => {
    const wrapper = mount(JrcCampaignsPage, { global });
    await flushPromises();
    let resolveOlder;
    api.analytics.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOlder = resolve;
        })
    );
    wrapper.vm.period = '7';
    await flushPromises();
    const latest = {
      summary: { sent: 7 },
      previous_summary: {},
      series: [],
      failure_reasons: [],
    };
    api.analytics.mockResolvedValueOnce({ data: latest });
    wrapper.vm.period = 'all';
    await flushPromises();
    resolveOlder({ data: { ...latest, summary: { sent: 99 } } });
    await flushPromises();
    expect(wrapper.vm.analytics.summary.sent).toBe(7);
    expect(wrapper.vm.analyticsLoading).toBe(false);
  });

  it('does not show a late refresh error after the page was disposed', async () => {
    const wrapper = mount(JrcCampaignsPage, { global });
    await flushPromises();
    let rejectPending;
    api.get.mockImplementationOnce(
      () =>
        new Promise((_resolve, reject) => {
          rejectPending = reject;
        })
    );
    const pending = wrapper.vm.fetchData();
    wrapper.unmount();
    rejectPending(new Error('Synthetic failure'));
    await pending;
    expect(useAlert).not.toHaveBeenCalled();
  });
});
