import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import CampaignWizard from '../components/CampaignWizard.vue';
import CampaignApproval from '../components/CampaignApproval.vue';
import api from 'dashboard/api/jrcCampaigns';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/routes/dashboard/jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ enabled: false }),
}));
vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: {
    audiencePreview: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    launch: vi.fn(),
    requestReview: vi.fn(),
    approve: vi.fn(),
  },
}));
enableAutoUnmount(afterEach);

const contacts = Array.from({ length: 511 }, (_, index) => ({
  selection_key: `contact:${index + 1}`,
  name: `Synthetic ${String(index + 1).padStart(3, '0')}`,
}));
const metadata = {
  source_inboxes: [],
  whatsapp_inboxes: [8, 9].map(id => ({
    id,
    name: `Sender ${id}`,
    connector: 'evolution',
    health_status: 'CONNECTED',
  })),
};
const preview = (payload, options = {}) => {
  const config = payload.audience_config;
  const selected = contacts.filter(contact =>
    config.recipient_selection_mode === 'include'
      ? config.recipient_selection_keys.includes(contact.selection_key)
      : !config.recipient_selection_keys.includes(contact.selection_key)
  );
  const filtered = contacts.filter(contact =>
    contact.name.includes(options.recipient_search || '')
  );
  const page = options.recipient_page || 1;
  return {
    data: {
      available_recipients: 511,
      estimated_recipients: selected.length,
      selection_confirmation: {
        count: selected.length,
        digest: selected.map(contact => contact.selection_key).join('|'),
      },
      recipients: filtered
        .slice((page - 1) * 50, page * 50)
        .map(contact => ({ ...contact, selected: selected.includes(contact) })),
      recipient_pagination: {
        page,
        per_page: 50,
        total: filtered.length,
        total_pages: Math.max(1, Math.ceil(filtered.length / 50)),
      },
    },
  };
};

describe('manual campaign audience on first creation', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    vi.clearAllMocks();
    api.audiencePreview.mockImplementation(async (...args) => preview(...args));
    api.create.mockImplementation(async ({ campaign }) => ({
      data: {
        ...JSON.parse(JSON.stringify(campaign)),
        id: 17,
        estimated_recipients: 4,
      },
    }));
    api.update.mockImplementation(async (_, payload) => api.create(payload));
  });
  afterEach(() => vi.useRealTimers());

  it('keeps exactly four of 511 through sender choice, navigation, create payload and reopening', async () => {
    const wrapper = mount(CampaignWizard, {
      props: { metadata },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    wrapper.vm.form.name = 'Only four';
    await wrapper.vm.openRecipientManager();
    wrapper.vm.setAllRecipients(false);
    wrapper.vm.recipientRows
      .slice(0, 4)
      .forEach(row => wrapper.vm.toggleRecipient(row));
    await vi.advanceTimersByTimeAsync(500);
    expect(wrapper.vm.eligibleCount).toBe(4);
    await wrapper.vm.nextStep();
    wrapper.vm.toggleSendingInbox(metadata.whatsapp_inboxes[0]);
    await flushPromises();
    await vi.advanceTimersByTimeAsync(500);
    expect(wrapper.vm.form.audience_config.recipient_selection_mode).toBe(
      'include'
    );
    expect(wrapper.vm.eligibleCount).toBe(4);
    wrapper.vm.form.steps[0].kind = 'text';
    wrapper.vm.form.steps[0].body = 'Synthetic message';
    await wrapper.vm.nextStep();
    await wrapper.vm.nextStep();
    wrapper.vm.goToStep(0);
    expect(wrapper.vm.eligibleCount).toBe(4);
    await wrapper.vm.save(true);
    const saved = api.create.mock.calls[0][0].campaign;
    expect(saved.audience_type).toBe('all_contacts');
    expect(saved.audience_config.recipient_selection_keys).toEqual([
      'contact:1',
      'contact:2',
      'contact:3',
      'contact:4',
    ]);
    expect(saved.audience_config.selection_confirmation.count).toBe(4);
    expect(api.launch).not.toHaveBeenCalled();
    const reopened = mount(CampaignWizard, {
      props: {
        metadata,
        campaign: {
          ...saved,
          id: 17,
          campaign_inboxes: saved.campaign_inboxes_attributes,
          steps: saved.steps_attributes,
        },
      },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    expect(reopened.vm.eligibleCount).toBe(4);
    expect(
      reopened.vm.buildPayload().audience_config.recipient_selection_keys
    ).toEqual(saved.audience_config.recipient_selection_keys);
    await reopened.vm.save(false);
    expect(api.update).toHaveBeenCalledWith(17, {
      campaign: expect.objectContaining({
        audience_config: expect.objectContaining({
          recipient_selection_mode: 'include',
          recipient_selection_keys: [
            'contact:1',
            'contact:2',
            'contact:3',
            'contact:4',
          ],
        }),
      }),
    });
  });

  it('selects all 511, clears all and keeps individual choices across search and pagination', async () => {
    const wrapper = mount(CampaignWizard, {
      props: { metadata },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    wrapper.vm.form.name = 'Paged selection';
    await wrapper.vm.openRecipientManager();
    const next = wrapper
      .get('footer')
      .findAll('button')
      .find(button => button.text() === 'JRC_CAMPAIGNS.WIZARD.NEXT');
    wrapper.vm.setAllRecipients(true);
    await vi.advanceTimersByTimeAsync(500);
    expect(wrapper.vm.eligibleCount).toBe(511);
    wrapper.vm.setAllRecipients(false);
    await vi.advanceTimersByTimeAsync(500);
    expect(wrapper.vm.eligibleCount).toBe(0);
    expect(wrapper.vm.currentStepValid).toBe(false);
    expect(next.element.disabled).toBe(true);
    wrapper.vm.toggleRecipient(wrapper.vm.recipientRows[0]);
    await flushPromises();
    expect(wrapper.vm.currentStepValid).toBe(false);
    expect(next.element.disabled).toBe(true);
    await vi.advanceTimersByTimeAsync(500);
    expect(wrapper.vm.currentStepValid).toBe(true);
    expect(next.element.disabled).toBe(false);
    await wrapper.vm.changeRecipientPage(2);
    wrapper.vm.toggleRecipient(wrapper.vm.recipientRows[0]);
    wrapper.vm.recipientSearch = 'Synthetic 511';
    await vi.advanceTimersByTimeAsync(500);
    expect(wrapper.vm.recipientRows).toHaveLength(1);
    wrapper.vm.toggleRecipient(wrapper.vm.recipientRows[0]);
    wrapper.vm.recipientSearch = '';
    await vi.advanceTimersByTimeAsync(500);
    await wrapper.vm.changeRecipientPage(1);
    expect(wrapper.vm.recipientRows[0].selected).toBe(true);
    expect(wrapper.vm.form.audience_config.recipient_selection_keys).toEqual([
      'contact:1',
      'contact:51',
      'contact:511',
    ]);
    expect(wrapper.vm.eligibleCount).toBe(3);
  });

  it('does not advance if the fresh preview becomes empty or fails', async () => {
    const wrapper = mount(CampaignWizard, {
      props: { metadata },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    wrapper.vm.form.name = 'Refresh before advancing';
    expect(wrapper.vm.currentStepValid).toBe(true);
    api.audiencePreview.mockResolvedValueOnce({
      data: { estimated_recipients: 0 },
    });
    await wrapper.vm.nextStep();
    expect(wrapper.vm.stepIndex).toBe(0);
    api.audiencePreview.mockRejectedValueOnce(new Error('Synthetic failure'));
    await wrapper.vm.refreshAudiencePreview();
    expect(wrapper.vm.currentStepValid).toBe(false);
  });

  it('ignores preview and recipient-page responses that precede the latest selection', async () => {
    const wrapper = mount(CampaignWizard, {
      props: { metadata },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    await wrapper.vm.openRecipientManager();
    let resolvePreview;
    let resolvePage;
    const old = preview(
      JSON.parse(
        JSON.stringify({ audience_config: wrapper.vm.form.audience_config })
      )
    );
    api.audiencePreview.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolvePreview = resolve;
        })
    );
    const pendingPreview = wrapper.vm.refreshAudiencePreview();
    api.audiencePreview.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolvePage = resolve;
        })
    );
    const pendingPage = wrapper.vm.refreshRecipientManager();
    wrapper.vm.setAllRecipients(false);
    wrapper.vm.toggleRecipient(wrapper.vm.recipientRows[0]);
    await vi.advanceTimersByTimeAsync(500);
    resolvePreview(old);
    resolvePage(old);
    await Promise.all([pendingPreview, pendingPage]);
    expect(wrapper.vm.eligibleCount).toBe(1);
    expect(wrapper.vm.recipientRows[1].selected).toBe(false);
    expect(wrapper.vm.form.audience_config.recipient_selection_keys).toEqual([
      'contact:1',
    ]);
  });

  it('does not open approval if the persisted create response differs from the selected count', async () => {
    const wrapper = mount(CampaignWizard, {
      props: { metadata },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    wrapper.vm.form.name = 'Mismatch';
    await wrapper.vm.openRecipientManager();
    wrapper.vm.setAllRecipients(false);
    wrapper.vm.toggleRecipient(wrapper.vm.recipientRows[0]);
    wrapper.vm.toggleSendingInbox(metadata.whatsapp_inboxes[0]);
    wrapper.vm.form.steps[0].kind = 'text';
    wrapper.vm.form.steps[0].body = 'Synthetic';
    await vi.advanceTimersByTimeAsync(500);
    api.create.mockResolvedValueOnce({
      data: { id: 17, estimated_recipients: 511 },
    });
    await wrapper.vm.save(true);
    expect(wrapper.emitted('reviewRequested')).toBeUndefined();
    expect(api.launch).not.toHaveBeenCalled();
  });

  it.each([0, 511])(
    'blocks final approval when the review shows %s instead of four',
    async count => {
      api.requestReview.mockResolvedValueOnce({
        data: {
          estimated_recipients: count,
          audience_config: { selection_confirmation: { count: 4 } },
          review_snapshot: {
            recipients: Array.from({ length: count }, (_, id) => ({
              destination: String(id),
            })),
          },
          campaign_inboxes: [],
          steps: [],
          sending_window: { days: [] },
          review_digest: 'synthetic',
        },
      });
      const wrapper = mount(CampaignApproval, {
        props: { campaign: { id: 17, estimated_recipients: 4 } },
      });
      await flushPromises();
      wrapper.vm.accepted = true;
      await wrapper.vm.approve();
      expect(api.approve).not.toHaveBeenCalled();
      expect(wrapper.get('[role="alert"]').text()).toBe(
        'JRC_CAMPAIGNS.GOVERNANCE.AUDIENCE_CHANGED'
      );
    }
  );
});
