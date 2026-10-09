import { beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import SurveyPreparationPanel from './SurveyPreparationPanel.vue';
import SurveyDeliveryPanel from './SurveyDeliveryPanel.vue';
import RecordEditor from './RecordEditor.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  qr: vi.fn(),
  api: {
    surveyLink: vi.fn(),
    surveyVoicePreview: vi.fn(),
    validateSurveyVoice: vi.fn(),
    channels: vi.fn(),
    deliverSurvey: vi.fn(),
    nativeCsat: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('qrcode', () => ({ default: { toDataURL: mocks.qr } }));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));
vi.mock(
  'dashboard/components/widgets/conversation/WhatsappTemplates/Modal.vue',
  () => ({
    default: {
      name: 'WhatsappTemplatesModal',
      props: ['show', 'inboxId'],
      emits: ['onSend', 'cancel', 'update:show'],
      template: '<section data-testid="official-template-modal" />',
    },
  })
);
const menu = () => ({
  account_id: 12,
  survey_id: 51,
  definition_version: 3,
  dry_run: true,
  persisted: false,
  external_status: 'not_configured',
  questions: [
    {
      key: 'rating',
      text: 'Pinned rating',
      type: 'scale',
      min: 0,
      max: 10,
      max_digits: 2,
      terminator: '#',
    },
    {
      key: 'choice',
      text: 'Pinned reason',
      type: 'choice',
      options: [{ digit: '1', label: 'Service', value: 'service' }],
    },
  ],
});
const signed = () =>
  `${window.location.origin}/jrc/relacionamento/pesquisas/native-signed-survey-token`;
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '12' } });
  mocks.store = { getters: reactive({ getCurrentUserID: 7 }) };
  mocks.api.surveyLink.mockResolvedValue({ data: { url: signed() } });
  mocks.qr.mockResolvedValue('data:image/png;base64,synthetic-qr-fixture');
  mocks.api.surveyVoicePreview.mockResolvedValue({ data: menu() });
  mocks.api.validateSurveyVoice.mockResolvedValue({
    data: {
      ...menu(),
      response_preview: { score: 10, classification: 'promoter' },
    },
  });
  mocks.api.channels.mockResolvedValue({
    data: {
      channel_conversations: [
        {
          id: 41,
          display_id: 19,
          inbox: 'Approved inbox',
          inbox_id: 31,
          can_reply: false,
          supports_whatsapp_templates: true,
        },
      ],
    },
  });
  mocks.api.deliverSurvey.mockResolvedValue({
    data: { message_id: 61, conversation_id: 19 },
  });
});

describe('R4 native signed survey preparation and explicit Meta reuse', () => {
  it('encodes the exact signed URL and submits voice inputs only through the read-only dry-run API', async () => {
    const wrapper = mount(SurveyPreparationPanel, {
      props: { survey: { id: 51, definition_version: 3 } },
    });
    await flushPromises();
    expect(mocks.qr).toHaveBeenCalledWith(signed(), { width: 240, margin: 2 });
    expect(wrapper.get('a').attributes('href')).toBe(signed());
    expect(wrapper.text()).toContain('Pinned rating');
    await wrapper.get('input').setValue('10');
    await wrapper.get('select').setValue('1');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.api.validateSurveyVoice).toHaveBeenCalledWith(
      '12',
      51,
      { rating: 10, choice: '1' },
      { signal: expect.any(AbortSignal) }
    );
    expect(wrapper.text()).toContain(
      'RELATIONSHIP.SURVEY_PREPARATION.VERIFIED'
    );
    expect(mocks.api.deliverSurvey).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('rejects an unrelated signed link before generating QR or fetching voice data', async () => {
    mocks.api.surveyLink.mockResolvedValue({
      data: {
        url: 'https://other-company.example/jrc/relacionamento/pesquisas/foreign',
      },
    });
    const wrapper = mount(SurveyPreparationPanel, {
      props: { survey: { id: 51, definition_version: 3 } },
    });
    await flushPromises();
    expect(mocks.qr).not.toHaveBeenCalled();
    expect(mocks.api.surveyVoicePreview).not.toHaveBeenCalled();
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.get('[role="alert"]').text()).toContain('UNVERIFIED');
    wrapper.unmount();
  });

  it('does not render a mismatched definition/account voice readback as verified', async () => {
    mocks.api.surveyVoicePreview.mockResolvedValue({
      data: { ...menu(), account_id: 13, definition_version: 2 },
    });
    const wrapper = mount(SurveyPreparationPanel, {
      props: { survey: { id: 51, definition_version: 3 } },
    });
    await flushPromises();
    expect(wrapper.find('form').exists()).toBe(false);
    expect(wrapper.get('[role="alert"]').text()).toContain('UNVERIFIED');
    wrapper.unmount();
  });

  it('discards stale signed links after an account switch', async () => {
    let complete;
    mocks.api.surveyLink.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          complete = resolve;
        })
    );
    mocks.api.surveyVoicePreview.mockResolvedValue({
      data: { ...menu(), account_id: 13 },
    });
    const wrapper = mount(SurveyPreparationPanel, {
      props: { survey: { id: 51, definition_version: 3 } },
    });
    mocks.route.params.accountId = '13';
    await flushPromises();
    complete({
      data: {
        url: `${window.location.origin}/jrc/relacionamento/pesquisas/old-account-token`,
      },
    });
    await flushPromises();
    expect(mocks.qr.mock.calls.flat().join()).not.toContain(
      'old-account-token'
    );
    expect(wrapper.get('a').attributes('href')).toBe(signed());
    wrapper.unmount();
  });

  it('uses the official existing template modal for the explicitly selected inbox when the free-text window is closed', async () => {
    const wrapper = mount(SurveyDeliveryPanel, {
      props: { assignmentId: 19, surveyId: 51 },
    });
    await flushPromises();
    expect(wrapper.get('select').element.value).toBe('');
    await wrapper.get('select').setValue('41');
    expect(
      wrapper.get('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
    await wrapper.get('form').trigger('submit');
    expect(mocks.api.deliverSurvey).not.toHaveBeenCalled();
    const templateButton = wrapper
      .findAll('button')
      .find(button => button.text() === 'RELATIONSHIP.SURVEY_TEMPLATE_SELECT');
    await templateButton.trigger('click');
    await flushPromises();
    const official = wrapper.findComponent({ name: 'WhatsappTemplatesModal' });
    expect(official.props('inboxId')).toBe(31);
    const payload = {
      message: `Survey: ${signed()}`,
      templateParams: {
        name: 'approved_native',
        language: 'pt_BR',
        namespace: 'native',
        category: 'UTILITY',
        processed_params: { body: { 1: signed() } },
      },
    };
    official.vm.$emit('onSend', payload);
    await flushPromises();
    expect(mocks.api.deliverSurvey).toHaveBeenCalledWith('12', 51, 41, payload);
    expect(wrapper.emitted('sent')).toEqual([
      [{ message_id: 61, conversation_id: 19 }],
    ]);
    expect(mocks.api.nativeCsat).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('does not expose Meta on an email inbox or invent a selected conversation', async () => {
    mocks.api.channels.mockResolvedValue({
      data: {
        channel_conversations: [
          {
            id: 41,
            display_id: 19,
            inbox: 'Email',
            inbox_id: 31,
            can_reply: true,
            supports_whatsapp_templates: false,
          },
        ],
      },
    });
    const wrapper = mount(SurveyDeliveryPanel, {
      props: { assignmentId: 19, surveyId: 51 },
    });
    await flushPromises();
    expect(wrapper.get('select').element.value).toBe('');
    await wrapper.get('select').setValue('41');
    expect(
      wrapper
        .findAll('button')
        .some(button => button.text() === 'RELATIONSHIP.SURVEY_TEMPLATE_SELECT')
    ).toBe(false);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.api.deliverSurvey).toHaveBeenCalledWith('12', 51, 41);
    wrapper.unmount();
  });

  it('requires an explicit authorized signed renewal successor instead of selecting the first candidate', async () => {
    const wrapper = mount(RecordEditor, {
      props: {
        kind: 'renewals',
        record: {
          id: 11,
          assignment_id: 19,
          status: 'won',
          lock_version: 2,
          commercial_context: {
            successor_contracts: [
              { id: 71, number: 'Approved A' },
              { id: 72, number: 'Approved B' },
            ],
          },
        },
        customers: [[19, 'Customer']],
      },
      global: { stubs: { SlaSummary: true, WorkContextPanel: true } },
    });
    const selection = wrapper.get('[data-testid="renewal-successor"]');
    expect(selection.element.value).toBe('');
    await selection.setValue('72');
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('save')[0][0]).toMatchObject({
      renewed_contract_id: 72,
      lock_version: 2,
      status: 'won',
    });
    wrapper.unmount();
  });
});
