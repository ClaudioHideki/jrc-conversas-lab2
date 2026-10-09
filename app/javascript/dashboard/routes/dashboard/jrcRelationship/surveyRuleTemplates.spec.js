import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import SurveyRuleTemplatePanel from './SurveyRuleTemplatePanel.vue';
import SurveyAdministrationPanel from './SurveyAdministrationPanel.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: {
    surveyDefinitions: vi.fn(),
    surveyRules: vi.fn(),
    surveyOrigins: vi.fn(),
    saveSurveyConfiguration: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));
const officialModalStub = {
  name: 'WhatsappTemplatesModal',
  props: ['show', 'inboxId'],
  emits: ['onSend', 'cancel', 'update:show'],
  template: '<div data-testid="official-rule-template-modal" />',
};
const global = { stubs: { WhatsappTemplatesModal: officialModalStub } };
const parsed = () => ({
  message: 'Pesquisa: {{survey_url}}',
  templateParams: {
    name: 'approved_rule_survey',
    language: 'pt_BR',
    category: 'UTILITY',
    namespace: 'native-rule',
    processed_params: { body: { 1: '{{survey_url}}' } },
  },
});
const panel = props =>
  mount(SurveyRuleTemplatePanel, {
    props: {
      inboxId: 51,
      executorId: 7,
      inboxes: [[51, 'Current WhatsApp inbox']],
      ...props,
    },
    global,
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '12' } });
  mocks.store = { getters: reactive({ getCurrentUserID: 7 }) };
  mocks.api.surveyDefinitions.mockResolvedValue({
    data: { payload: [{ id: 4, name: 'Published NPS', settings: {} }] },
  });
  mocks.api.surveyRules.mockResolvedValue({ data: { payload: [] } });
  mocks.api.surveyOrigins.mockResolvedValue({ data: { payload: [] } });
  mocks.api.saveSurveyConfiguration.mockResolvedValue({ data: {} });
});

describe('Optional versioned official Meta survey templates', () => {
  it('opens the existing modal for the explicit inbox and captures its parser payload without calling a delivery API', async () => {
    const wrapper = panel();
    await wrapper
      .get('[data-testid="survey-rule-template-open"]')
      .trigger('click');
    const modal = wrapper.getComponent({ name: 'WhatsappTemplatesModal' });
    expect(modal.props('inboxId')).toBe(51);
    const payload = parsed();
    modal.vm.$emit('onSend', payload);
    await flushPromises();
    const result = wrapper.emitted('update:modelValue')[0][0];
    expect(result).toEqual({
      inbox_id: 51,
      content: payload.message,
      template_params: payload.templateParams,
    });
    payload.templateParams.name = 'Changed after parser event';
    expect(result.template_params.name).toBe('approved_rule_survey');
    expect(
      wrapper.find('[data-testid="official-rule-template-modal"]').exists()
    ).toBe(false);
    expect(mocks.api.saveSurveyConfiguration).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('requires both the explicit approved WhatsApp inbox and execution member without selecting the first option', async () => {
    const wrapper = panel({ inboxId: null, executorId: null });
    expect(
      wrapper.get('[data-testid="survey-rule-template-open"]').element.disabled
    ).toBe(true);
    await wrapper.setProps({ inboxId: 52, executorId: 7 });
    expect(
      wrapper.get('[data-testid="survey-rule-template-open"]').element.disabled
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="official-rule-template-modal"]').exists()
    ).toBe(false);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    wrapper.unmount();
  });

  it('rejects a parser payload without the reserved marker in a native BODY parameter', async () => {
    const wrapper = panel();
    await wrapper
      .get('[data-testid="survey-rule-template-open"]')
      .trigger('click');
    const payload = parsed();
    payload.templateParams.processed_params.body[1] = 'Unrelated value';
    wrapper
      .getComponent({ name: 'WhatsappTemplatesModal' })
      .vm.$emit('onSend', payload);
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('MARKER_REQUIRED');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    wrapper.unmount();
  });

  it.each(['account', 'operator', 'executor', 'inbox'])(
    'closes and discards stale modal results on %s changes',
    async kind => {
      const wrapper = panel();
      const changes = {
        account: () => {
          mocks.route.params.accountId = '13';
        },
        operator: () => {
          mocks.store.getters.getCurrentUserID = 8;
        },
        executor: () => wrapper.setProps({ executorId: 8 }),
        inbox: () => wrapper.setProps({ inboxId: 52 }),
      };
      await wrapper
        .get('[data-testid="survey-rule-template-open"]')
        .trigger('click');
      const modal = wrapper.getComponent({ name: 'WhatsappTemplatesModal' });
      await changes[kind]();
      await flushPromises();
      modal.vm.$emit('onSend', parsed());
      await flushPromises();
      expect(
        wrapper.find('[data-testid="official-rule-template-modal"]').exists()
      ).toBe(false);
      expect(wrapper.emitted('update:modelValue')).toBeUndefined();
      wrapper.unmount();
    }
  );

  it('removes configuration explicitly and invalidates an existing selection when the delivery inbox changes', async () => {
    const selected = {
      inbox_id: 51,
      content: parsed().message,
      template_params: parsed().templateParams,
      template_fingerprint: 'a'.repeat(64),
    };
    const wrapper = panel({ modelValue: selected });
    expect(
      wrapper.get('[data-testid="survey-rule-template-selection"]').text()
    ).toContain('approved_rule_survey');
    await wrapper
      .get('[data-testid="survey-rule-template-remove"]')
      .trigger('click');
    await wrapper.setProps({ inboxId: 52 });
    expect(wrapper.emitted('update:modelValue')).toEqual([[null], [null]]);
    expect(selected.template_fingerprint).toBe('a'.repeat(64));
    wrapper.unmount();
  });

  it('saves the parser selection through existing rule configuration while the new rule remains OFF', async () => {
    const wrapper = mount(SurveyAdministrationPanel, {
      props: {
        allowed: true,
        metadata: {
          execution_members: [[7, 'CS']],
          survey_inboxes: [[51, 'WhatsApp']],
          survey_whatsapp_inboxes: [[51, 'WhatsApp']],
        },
      },
      global,
    });
    await flushPromises();
    await wrapper.findAll('nav button')[2].trigger('click');
    await wrapper.get('[data-testid="new-survey-config"]').trigger('click');
    await wrapper
      .get('[data-testid="survey-rule-channel"]')
      .setValue('whatsapp');
    await wrapper.get('[data-testid="survey-rule-inbox"]').setValue('51');
    await wrapper.get('[data-testid="survey-rule-executor"]').setValue('7');
    await wrapper
      .get('[data-testid="survey-rule-template-open"]')
      .trigger('click');
    wrapper
      .getComponent({ name: 'WhatsappTemplatesModal' })
      .vm.$emit('onSend', parsed());
    await flushPromises();
    await wrapper.get('[data-testid="survey-config-form"]').trigger('submit');
    expect(mocks.api.saveSurveyConfiguration).toHaveBeenCalledWith(
      '12',
      'rules',
      expect.objectContaining({
        active: false,
        execution_member_id: 7,
        settings: expect.objectContaining({
          channel: 'whatsapp',
          delivery_inbox_id: 51,
          whatsapp_template: {
            inbox_id: 51,
            content: parsed().message,
            template_params: parsed().templateParams,
          },
        }),
      })
    );
    wrapper.unmount();
  });
});
