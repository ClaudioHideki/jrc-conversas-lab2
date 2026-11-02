import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import JrcCampaignsPage from '../JrcCampaignsPage.vue';
import CampaignWizard from '../components/CampaignWizard.vue';
import CampaignAudienceInput from '../components/CampaignAudienceInput.vue';
import api from 'dashboard/api/jrcCampaigns';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/routes/dashboard/jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ enabled: false }),
}));
vi.mock('dashboard/api/jrcCampaigns', () => ({
  default: {
    get: vi.fn(),
    metadata: vi.fn(),
    analytics: vi.fn(),
    audiencePreview: vi.fn(),
    createSanitizedList: vi.fn(),
    uploadMedia: vi.fn(),
    create: vi.fn(),
    requestReview: vi.fn(),
    approve: vi.fn(),
    launch: vi.fn(),
  },
}));
enableAutoUnmount(afterEach);

const sender = {
  id: 8,
  name: 'Synthetic connected sender',
  phone_number: '+551155550008',
  connector: 'broker',
  health_status: 'CONNECTED',
  min_interval_seconds: 60,
};
const savedCampaign = {
  id: 17,
  name: 'Synthetic image campaign',
  status: 'draft',
  approval_valid: false,
  created_at: '2026-10-26T12:00:00Z',
  delivery_channel: 'whatsapp',
  audience_type: 'sanitized_list',
  audience_config: { sanitized_list_id: 42 },
  rotation_mode: 'round_robin',
  conversation_mode: 'reply_only',
  trigger_type: 'manual',
  scheduled_at: null,
  recurrence_config: { type: 'none', interval_days: 7 },
  follow_up_config: { on_reply_label_id: null, on_reply_stage_id: null },
  delay_min_seconds: 60,
  delay_max_seconds: 60,
  sending_window: {
    days: [1, 2, 3, 4, 5],
    start: '08:00',
    end: '18:00',
    timezone: 'America/Sao_Paulo',
  },
  campaign_inboxes: [{ id: 91, inbox_id: 8, name: sender.name, enabled: true }],
  steps: [
    {
      id: 92,
      position: 0,
      kind: 'image',
      body: 'Olá {{nome}}, conheça nossa oferta.',
      media_asset_id: 73,
      media_url: 'https://media.example.test/synthetic-image.png',
      file_name: 'synthetic-image.png',
    },
  ],
  review_digest: 'synthetic-image-audience-digest',
  review_snapshot: {
    configuration: {},
    recipients: [
      { name: 'Synthetic Ana', destination: '+5511999990001' },
      { name: 'Synthetic Bia', destination: '+5511999990002' },
    ],
  },
};

describe('campaign direct audience and captioned image module flow', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    vi.clearAllMocks();
    api.get.mockResolvedValue({ data: [] });
    api.metadata.mockResolvedValue({
      data: {
        account_timezone: 'America/Sao_Paulo',
        whatsapp_inboxes: [sender],
        source_inboxes: [],
        email_inboxes: [],
        sanitized_lists: [],
        labels: [],
        pipelines: [],
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
    api.audiencePreview.mockResolvedValue({
      data: {
        estimated_recipients: 2,
        available_recipients: 2,
        sample: savedCampaign.review_snapshot.recipients,
      },
    });
    api.createSanitizedList.mockResolvedValue({
      data: { id: 42, name: savedCampaign.name, stats: { valid_phone: 2 } },
    });
    api.uploadMedia.mockResolvedValue({
      data: {
        id: 73,
        url: 'https://media.example.test/synthetic-image.png',
        file_name: 'synthetic-image.png',
      },
    });
    api.create.mockResolvedValue({ data: savedCampaign });
    api.requestReview.mockResolvedValue({ data: savedCampaign });
    api.approve.mockResolvedValue({
      data: { ...savedCampaign, approval_valid: true },
    });
    api.launch.mockResolvedValue({
      data: { ...savedCampaign, status: 'running' },
    });
  });
  afterEach(() => vi.useRealTimers());

  it.each(['manual', 'csv'])(
    'takes a %s list through one captioned image, explicit sender, audited approval and a separate start',
    async mode => {
      const recipients =
        mode === 'manual'
          ? [
              { name: '', destination: '+5511999990001' },
              { name: '', destination: '+5511999990002' },
            ]
          : savedCampaign.review_snapshot.recipients;
      const reviewedCampaign = {
        ...savedCampaign,
        review_snapshot: { configuration: {}, recipients },
      };
      api.audiencePreview.mockResolvedValue({
        data: {
          estimated_recipients: 2,
          available_recipients: 2,
          sample: recipients,
        },
      });
      api.create.mockResolvedValue({ data: reviewedCampaign });
      api.requestReview.mockResolvedValue({ data: reviewedCampaign });
      const wrapper = mount(JrcCampaignsPage, {
        global: {
          mocks: { $t: key => key },
          stubs: { CampaignPerformanceChart: true },
        },
      });
      await flushPromises();
      await wrapper
        .findAll('button')
        .find(button => button.text() === 'JRC_CAMPAIGNS.NEW_CAMPAIGN')
        .trigger('click');
      const wizard = wrapper.getComponent(CampaignWizard);
      await wizard
        .get('input[placeholder="JRC_CAMPAIGNS.WIZARD.NAME_PLACEHOLDER"]')
        .setValue('Synthetic image campaign');
      await wizard
        .findAll('button')
        .find(button =>
          button
            .text()
            .includes(
              mode === 'manual'
                ? 'JRC_CAMPAIGNS.WIZARD.SOURCE_MANUAL'
                : 'JRC_CAMPAIGNS.WIZARD.SOURCE_IMPORT'
            )
        )
        .trigger('click');
      const audience = wizard.getComponent(CampaignAudienceInput);
      if (mode === 'manual') {
        await audience.get('textarea').setValue('5511999990001\n5511999990002');
      } else {
        const fileInput = audience.get('input[type="file"]');
        Object.defineProperty(fileInput.element, 'files', {
          value: [
            {
              text: async () =>
                'nome;telefone\nSynthetic Ana;5511999990001\nSynthetic Bia;5511999990002',
            },
          ],
        });
        await fileInput.trigger('change');
        await flushPromises();
      }
      await audience.get('button').trigger('click');
      await flushPromises();
      expect(api.createSanitizedList).toHaveBeenCalledExactlyOnceWith({
        name: 'Synthetic image campaign',
        entries:
          mode === 'manual'
            ? [{ phone: '5511999990001' }, { phone: '5511999990002' }]
            : [
                { name: 'Synthetic Ana', phone: '5511999990001', email: '' },
                { name: 'Synthetic Bia', phone: '5511999990002', email: '' },
              ],
      });
      await wizard
        .get('footer')
        .findAll('button')
        .find(button => button.text() === 'JRC_CAMPAIGNS.WIZARD.NEXT')
        .trigger('click');
      await flushPromises();
      const senderChoice = wizard
        .findAll('label')
        .find(label => label.text().includes('Synthetic connected sender'))
        .get('input[type="checkbox"]');
      expect(senderChoice.element.checked).toBe(false);
      await senderChoice.setValue(true);
      await wizard
        .get('footer')
        .findAll('button')
        .find(button => button.text() === 'JRC_CAMPAIGNS.WIZARD.NEXT')
        .trigger('click');
      await flushPromises();
      await wizard
        .findAll('select')
        .find(select => select.find('option[value="image"]').exists())
        .setValue('image');
      await wizard
        .get('textarea')
        .setValue('Olá {{nome}}, conheça nossa oferta.');
      const image = new File(['synthetic image'], 'synthetic-image.png', {
        type: 'image/png',
      });
      const mediaInput = wizard.get('input[type="file"]');
      Object.defineProperty(mediaInput.element, 'files', { value: [image] });
      await mediaInput.trigger('change');
      await flushPromises();
      expect(api.uploadMedia).toHaveBeenCalledExactlyOnceWith(image, 'image');
      await wizard
        .get('footer')
        .findAll('button')
        .find(button => button.text() === 'JRC_CAMPAIGNS.WIZARD.NEXT')
        .trigger('click');
      await flushPromises();
      await wizard.get('footer').findAll('button').at(-1).trigger('click');
      await flushPromises();

      expect(api.create).toHaveBeenCalledExactlyOnceWith({
        campaign: expect.objectContaining({
          audience_type: 'sanitized_list',
          audience_config: expect.objectContaining({ sanitized_list_id: 42 }),
          campaign_inboxes_attributes: [
            expect.objectContaining({ inbox_id: 8, enabled: true }),
          ],
          sending_window: {
            days: [1, 2, 3, 4, 5],
            start: '08:00',
            end: '18:00',
            timezone: 'America/Sao_Paulo',
          },
          steps_attributes: [
            expect.objectContaining({
              kind: 'image',
              position: 0,
              body: 'Olá {{nome}}, conheça nossa oferta.',
              media_asset_id: 73,
              media_url: 'https://media.example.test/synthetic-image.png',
              file_name: 'synthetic-image.png',
            }),
          ],
        }),
      });
      expect(api.requestReview).toHaveBeenCalledExactlyOnceWith(17);
      expect(api.launch).not.toHaveBeenCalled();
      const review = wrapper.get('[role="dialog"]');
      expect(review.text()).toContain('Synthetic connected sender');
      expect(review.text()).toContain('Olá {{nome}}, conheça nossa oferta.');
      expect(review.text()).toContain('+5511999990001');
      expect(review.text()).not.toContain('undefined');
      if (mode === 'csv') expect(review.text()).toContain('Synthetic Ana');
      else expect(review.text()).not.toContain('Synthetic Ana');
      await review.get('input[type="checkbox"]').setValue(true);
      api.get.mockResolvedValue({
        data: [{ ...savedCampaign, approval_valid: true }],
      });
      await review
        .findAll('button')
        .find(button => button.text() === 'JRC_CAMPAIGNS.GOVERNANCE.APPROVE')
        .trigger('click');
      await flushPromises();
      expect(api.approve).toHaveBeenCalledExactlyOnceWith(
        17,
        'synthetic-image-audience-digest'
      );
      expect(api.launch).not.toHaveBeenCalled();
      expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
      await wrapper.get('button[title="JRC_CAMPAIGNS.START"]').trigger('click');
      await flushPromises();
      expect(api.launch).toHaveBeenCalledExactlyOnceWith(17);
    }
  );
});
