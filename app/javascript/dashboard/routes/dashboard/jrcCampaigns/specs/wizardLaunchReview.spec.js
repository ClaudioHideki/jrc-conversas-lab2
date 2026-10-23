import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import CampaignWizard from '../components/CampaignWizard.vue';
import api from 'dashboard/api/jrcCampaigns';
import { useAlert } from 'dashboard/composables';
import CampaignFilters from 'dashboard/routes/dashboard/jrcCustomers/components/CampaignFilters.vue';

const { customerMaster } = vi.hoisted(() => ({
  customerMaster: { enabled: false },
}));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/routes/dashboard/jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => customerMaster,
}));
vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: {
    audiencePreview: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    launch: vi.fn(),
  },
}));
enableAutoUnmount(afterEach);

describe('campaign wizard launch and required human review', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    vi.clearAllMocks();
    customerMaster.enabled = false;
    api.audiencePreview.mockResolvedValue({
      data: { estimated_recipients: 1, sample: [] },
    });
    api.create.mockResolvedValue({
      data: {
        id: 17,
        name: 'QA campaign',
        status: 'draft',
        approval_valid: false,
      },
    });
    api.update.mockResolvedValue({
      data: {
        id: 17,
        name: 'QA campaign',
        status: 'draft',
        approval_valid: true,
      },
    });
    api.launch.mockResolvedValue({ data: { id: 17, status: 'running' } });
  });
  afterEach(() => vi.useRealTimers());

  it('refines the audience inside Contacts and keeps customer filters out of sender configuration', async () => {
    customerMaster.enabled = true;
    const wrapper = mount(CampaignWizard, {
      props: { metadata: { source_inboxes: [] } },
      global: {
        stubs: { CompanyPicker: true },
        mocks: { $t: key => key },
      },
    });
    await flushPromises();
    const source = wrapper.get('.campaign-source-panel');
    const filters = source.getComponent(CampaignFilters);
    expect(filters.text()).not.toMatch(/Consentimento.*obrigat/i);
    await filters.get('select').setValue('customer');
    await filters.findAll('input')[0].setValue('Synthetic segment');
    expect(wrapper.vm.buildPayload().audience_config.customer_filters).toEqual({
      relationship_type: 'customer',
      segment: 'Synthetic segment',
    });
    wrapper.vm.stepIndex = 1;
    await flushPromises();
    expect(wrapper.findComponent(CampaignFilters).exists()).toBe(false);
    expect(api.create).not.toHaveBeenCalled();
    expect(api.launch).not.toHaveBeenCalled();
  });

  it('clears customer filters when selecting a sanitized list and keeps them hidden in that audience', async () => {
    customerMaster.enabled = true;
    const wrapper = mount(CampaignWizard, {
      props: { metadata: { source_inboxes: [], sanitized_lists: [] } },
      global: {
        stubs: { CompanyPicker: true },
        mocks: { $t: key => key },
      },
    });
    await flushPromises();
    wrapper.vm.form.audience_config.customer_filters = { company_id: 17 };
    wrapper.vm.form.audience_type = 'sanitized_list';
    await flushPromises();
    expect(wrapper.findComponent(CampaignFilters).exists()).toBe(false);
    expect(wrapper.vm.buildPayload().audience_config.customer_filters).toEqual(
      {}
    );
    wrapper.vm.form.audience_type = 'all_contacts';
    await flushPromises();
    expect(wrapper.getComponent(CampaignFilters).props('modelValue')).toEqual(
      {}
    );
    expect(api.launch).not.toHaveBeenCalled();
  });

  it.each([
    ['evolution', 'whatsapp', 'text'],
    ['official', 'whatsapp', 'template'],
    ['email', 'email', 'email'],
  ])(
    'completes the four %s steps and opens review for the saved draft without attempting an unapproved launch',
    async (connector, channel, kind) => {
      const sender = {
        id: 8,
        name: 'QA sender',
        connector,
        health_status: 'CONNECTED',
      };
      const wrapper = mount(CampaignWizard, {
        props: {
          metadata: {
            whatsapp_inboxes: channel === 'whatsapp' ? [sender] : [],
            email_inboxes: channel === 'email' ? [sender] : [],
            source_inboxes: [],
          },
        },
        global: { mocks: { $t: key => key } },
      });
      await flushPromises();
      await wrapper
        .get('input[placeholder="JRC_CAMPAIGNS.WIZARD.NAME_PLACEHOLDER"]')
        .setValue('QA campaign');
      wrapper.vm.form.delivery_channel = channel;
      await flushPromises();
      await vi.advanceTimersByTimeAsync(650);
      wrapper.vm.form.steps[0] = {
        ...wrapper.vm.form.steps[0],
        kind,
        subject: 'QA subject',
        body: 'Synthetic message',
        template_name: 'qa_template',
        template_language: 'pt_BR',
      };
      await flushPromises();
      const advance = async () => {
        const index = wrapper.vm.stepIndex;
        const next = wrapper
          .get('footer')
          .findAll('button')
          .find(button => button.text() === 'JRC_CAMPAIGNS.WIZARD.NEXT');
        expect(
          next.element.disabled,
          JSON.stringify({
            index,
            form: wrapper.vm.form,
            preview: wrapper.vm.audiencePreview,
          })
        ).toBe(false);
        await next.trigger('click');
        await flushPromises();
        expect(wrapper.vm.stepIndex).toBe(index + 1);
      };
      await advance();
      if (!wrapper.vm.form.inboxLinks.length) {
        await wrapper
          .findAll('label')
          .find(label => label.text().includes('QA sender'))
          .get('input[type="checkbox"]')
          .setValue(true);
      }
      await advance();
      await advance();
      const start = wrapper.get('footer').findAll('button').at(-1);
      expect(start.element.disabled).toBe(false);
      await start.trigger('click');
      await flushPromises();
      expect(api.create).toHaveBeenCalledOnce();
      expect(api.create).toHaveBeenCalledWith({
        campaign: expect.objectContaining({
          delivery_channel: channel,
          steps_attributes: [expect.objectContaining({ kind })],
          campaign_inboxes_attributes: [
            expect.objectContaining({ inbox_id: 8 }),
          ],
        }),
      });
      expect(api.launch).not.toHaveBeenCalled();
      expect(wrapper.emitted('reviewRequested')).toEqual([
        [expect.objectContaining({ id: 17, approval_valid: false })],
      ]);
      expect(wrapper.emitted('saved')).toBeUndefined();
    }
  );

  it('launches the existing draft only when the update response confirms its approval is still valid', async () => {
    const wrapper = mount(CampaignWizard, {
      props: {
        metadata: {
          whatsapp_inboxes: [{ id: 8, connector: 'evolution' }],
          source_inboxes: [],
        },
        campaign: {
          id: 17,
          name: 'QA campaign',
          status: 'draft',
          approval_valid: true,
          campaign_inboxes: [{ inbox_id: 8, enabled: true }],
          steps: [{ kind: 'text', body: 'Synthetic message' }],
        },
      },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    await wrapper.vm.save(true);
    expect(api.update).toHaveBeenCalledOnce();
    expect(api.create).not.toHaveBeenCalled();
    expect(api.launch).toHaveBeenCalledExactlyOnceWith(17);
    expect(wrapper.emitted('saved')).toEqual([[]]);
    expect(wrapper.emitted('reviewRequested')).toBeUndefined();
  });

  it('does not open review or report success when saving fails', async () => {
    api.create.mockRejectedValueOnce({
      response: { data: { errors: ['Synthetic validation failure'] } },
    });
    const wrapper = mount(CampaignWizard, {
      props: {
        metadata: {
          whatsapp_inboxes: [{ id: 8, connector: 'evolution' }],
          source_inboxes: [],
        },
      },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    wrapper.vm.form.name = 'QA campaign';
    wrapper.vm.form.steps[0].kind = 'text';
    wrapper.vm.form.steps[0].body = 'Synthetic message';
    await wrapper.vm.save(true);
    expect(api.create).toHaveBeenCalledOnce();
    expect(api.launch).not.toHaveBeenCalled();
    expect(wrapper.emitted('reviewRequested')).toBeUndefined();
    expect(wrapper.emitted('saved')).toBeUndefined();
    expect(useAlert).toHaveBeenCalledWith('Synthetic validation failure');
    expect(wrapper.vm.saving).toBe(false);
  });

  it('keeps the selected sanitized audience independent from an explicitly chosen sending number and rotation order', async () => {
    const wrapper = mount(CampaignWizard, {
      props: {
        initialSanitizedListId: 7,
        metadata: {
          source_inboxes: [{ id: 11, name: 'QA source' }],
          sanitized_lists: [{ id: 7, name: 'QA list' }],
          whatsapp_inboxes: [
            {
              id: 8,
              name: 'QA Evolution',
              phone_number: '+551155550008',
              connector: 'evolution',
              health_status: 'CONNECTED',
            },
            {
              id: 9,
              name: 'QA Official',
              phone_number: '+551155550009',
              provider: 'whatsapp_cloud',
              health_status: 'CONNECTED',
            },
            {
              id: 10,
              name: 'QA Offline',
              phone_number: '+551155550010',
              health_status: 'DISCONNECTED',
            },
            {
              id: 12,
              name: 'QA Official 2',
              phone_number: '+551155550012',
              provider: 'whatsapp_cloud',
              health_status: 'CONNECTED',
            },
          ],
        },
      },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    wrapper.vm.stepIndex = 1;
    await flushPromises();
    expect(wrapper.vm.form.inboxLinks).toEqual([]);
    const labels = wrapper.findAll('label');
    const official = labels.find(label =>
      label.text().includes('+551155550009')
    );
    await official.get('input[type="checkbox"]').setValue(true);
    expect(wrapper.vm.buildPayload()).toEqual(
      expect.objectContaining({
        audience_type: 'sanitized_list',
        audience_config: expect.objectContaining({ sanitized_list_id: 7 }),
        campaign_inboxes_attributes: [expect.objectContaining({ inbox_id: 9 })],
      })
    );
    expect(
      labels.find(label => label.text().includes('+551155550010')).get('input')
        .element.disabled
    ).toBe(true);
    await labels
      .find(label => label.text().includes('+551155550012'))
      .get('input[type="checkbox"]')
      .setValue(true);
    await wrapper.get('input[type="radio"][value="priority"]').setValue();
    wrapper.vm.moveInbox(12, -1);
    expect(wrapper.vm.buildPayload()).toEqual(
      expect.objectContaining({
        rotation_mode: 'priority',
        campaign_inboxes_attributes: [
          expect.objectContaining({ inbox_id: 12, position: 0 }),
          expect.objectContaining({ inbox_id: 9, position: 1 }),
        ],
      })
    );
    expect(api.create).not.toHaveBeenCalled();
    expect(api.launch).not.toHaveBeenCalled();
    expect(wrapper.text()).not.toMatch(/JARVIS|JEV/);
    await labels
      .find(label => label.text().includes('+551155550008'))
      .get('input[type="checkbox"]')
      .setValue(true);
    expect(wrapper.get('[role="alert"]').text()).toBe(
      'JRC_CAMPAIGNS.GUIDE.SEPARATE_SENDERS'
    );
    expect(wrapper.vm.configValid).toBe(false);
    expect(api.launch).not.toHaveBeenCalled();
  });

  it('keeps a disabled sender link inactive until explicitly selected and preserves its persisted ID', async () => {
    const wrapper = mount(CampaignWizard, {
      props: {
        metadata: {
          whatsapp_inboxes: [
            {
              id: 8,
              name: 'QA disabled sender',
              phone_number: '+551155550008',
            },
          ],
          source_inboxes: [],
        },
        campaign: {
          id: 17,
          name: 'QA',
          campaign_inboxes: [{ id: 4, inbox_id: 8, enabled: false }],
          steps: [{ kind: 'text', body: 'Synthetic' }],
        },
      },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    wrapper.vm.stepIndex = 1;
    await flushPromises();
    expect(wrapper.vm.configValid).toBe(false);
    const checkbox = wrapper
      .findAll('label')
      .find(label => label.text().includes('+551155550008'))
      .get('input[type="checkbox"]');
    expect(checkbox.element.checked).toBe(false);
    await checkbox.setValue(true);
    expect(wrapper.vm.buildPayload().campaign_inboxes_attributes).toEqual([
      expect.objectContaining({ id: 4, inbox_id: 8, enabled: true }),
    ]);
    expect(wrapper.vm.configValid).toBe(true);
    expect(api.launch).not.toHaveBeenCalled();
  });

  it('uses the official-channel audience without requiring a consent panel or sending the draft', async () => {
    api.audiencePreview.mockResolvedValueOnce({
      data: { estimated_recipients: 2, sample: [] },
    });
    const wrapper = mount(CampaignWizard, {
      props: {
        metadata: {
          whatsapp_inboxes: [
            {
              id: 8,
              name: 'Official',
              connector: 'official',
              health_status: 'CONNECTED',
            },
          ],
          source_inboxes: [],
        },
      },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    wrapper.vm.form.name = 'Retained draft';
    expect(wrapper.text()).not.toContain('JRC_CAMPAIGNS.GUIDE.MANAGE_CONSENTS');
    expect(wrapper.findComponent({ name: 'ConsentPanel' }).exists()).toBe(
      false
    );
    expect(wrapper.vm.form.name).toBe('Retained draft');
    expect(wrapper.vm.eligibleCount).toBe(2);
    expect(api.create).not.toHaveBeenCalled();
    expect(api.launch).not.toHaveBeenCalled();
  });
  it('requires a new review when updating an approved draft invalidates its approval', async () => {
    api.update.mockResolvedValueOnce({
      data: { id: 17, status: 'draft', approval_valid: false },
    });
    const wrapper = mount(CampaignWizard, {
      props: {
        metadata: {
          whatsapp_inboxes: [{ id: 8, connector: 'evolution' }],
          source_inboxes: [],
        },
        campaign: {
          id: 17,
          name: 'QA campaign',
          status: 'draft',
          approval_valid: true,
          campaign_inboxes: [{ inbox_id: 8, enabled: true }],
          steps: [{ kind: 'text', body: 'Changed synthetic message' }],
        },
      },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    await wrapper.vm.save(true);
    expect(api.update).toHaveBeenCalledOnce();
    expect(api.launch).not.toHaveBeenCalled();
    expect(wrapper.emitted('reviewRequested')).toEqual([
      [expect.objectContaining({ id: 17, approval_valid: false })],
    ]);
    expect(wrapper.emitted('saved')).toBeUndefined();
  });
});
