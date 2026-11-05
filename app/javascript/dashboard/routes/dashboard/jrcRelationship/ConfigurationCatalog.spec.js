import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { expect, it, vi } from 'vitest';
import Configuration from './ConfigurationPanel.vue';
import RequiredDocumentsForm from './RequiredDocumentsForm.vue';
const mocks = vi.hoisted(() => ({
  configuration: vi.fn(),
  saveConfiguration: vi.fn(),
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1400' } }),
}));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: reactive({ getCurrentUserID: 1018 }) }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('./OperationsSettingsPanel.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('./PlaybookExecutionPanel.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('./PlaybookDesignPreview.vue', () => ({
  default: { template: '<div />' },
}));
it('saves fractional trend and SLA weights in the native versioned editor, allowing zero without replacing other rules', async () => {
  mocks.saveConfiguration.mockClear();
  const state = {
    scope_key: 'account',
    version: 9,
    weights: { adoption: 100 },
    rules: { required_documents: [], priority_trend: 0, priority_sla: 0 },
    history: [],
  };
  mocks.configuration.mockResolvedValue({ data: state });
  mocks.saveConfiguration.mockResolvedValue({ data: {} });
  const wrapper = mount(Configuration, {
    props: { allowed: true },
    global: { stubs: { PlaybookFlowPolicyForm: true } },
  });
  await flushPromises();
  const trend = wrapper.get('[data-testid="relationship-rule-priority_trend"]');
  const sla = wrapper.get('[data-testid="relationship-rule-priority_sla"]');
  expect([trend.attributes('min'), sla.attributes('min')]).toEqual(['0', '0']);
  expect([trend.attributes('step'), sla.attributes('step')]).toEqual([
    'any',
    'any',
  ]);
  await trend.setValue('0.25');
  await sla.setValue('0.5');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.saveConfiguration).toHaveBeenCalledWith(
    '1400',
    expect.objectContaining({
      scope_key: 'account',
      version: 9,
      rules: {
        required_documents: [],
        priority_trend: 0.25,
        priority_sla: 0.5,
      },
    })
  );
  await wrapper.setProps({ allowed: false });
  await flushPromises();
  expect(wrapper.find('form').exists()).toBe(false);
  wrapper.unmount();
});
it('saves the documentary catalog in the native scoped/versioned configuration and reloads persisted state', async () => {
  const entry = {
    code: 'proof',
    title: 'Synthetic proof',
    category: 'registration',
  };
  const state = {
    scope_key: 'account',
    version: 3,
    weights: { adoption: 100 },
    rules: { required_documents: [] },
    history: [],
  };
  mocks.configuration.mockResolvedValueOnce({ data: state }).mockResolvedValue({
    data: { ...state, version: 4, rules: { required_documents: [entry] } },
  });
  mocks.saveConfiguration.mockResolvedValue({ data: {} });
  const wrapper = mount(Configuration, {
    props: { allowed: true },
    global: { stubs: { PlaybookFlowPolicyForm: true } },
  });
  await flushPromises();
  wrapper
    .getComponent(RequiredDocumentsForm)
    .vm.$emit('update:modelValue', [entry]);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.saveConfiguration).toHaveBeenCalledWith(
    '1400',
    expect.objectContaining({
      scope_key: 'account',
      version: 3,
      rules: { required_documents: [entry] },
    })
  );
  expect(mocks.configuration).toHaveBeenCalledTimes(2);
  expect(
    wrapper.getComponent(RequiredDocumentsForm).props('modelValue')
  ).toEqual([entry]);
  await wrapper.setProps({ allowed: false });
  await flushPromises();
  expect(wrapper.findComponent(RequiredDocumentsForm).exists()).toBe(false);
  wrapper.unmount();
});

it('persists a recovery margin through the existing versioned configuration form and permits zero', async () => {
  const state = {
    scope_key: 'account',
    version: 7,
    weights: { adoption: 100 },
    rules: {
      required_documents: [],
      healthy_threshold: 80,
      health_hysteresis_points: 0,
    },
    history: [],
  };
  mocks.configuration.mockResolvedValue({ data: state });
  mocks.saveConfiguration.mockResolvedValue({ data: {} });
  const wrapper = mount(Configuration, {
    props: { allowed: true },
    global: { stubs: { PlaybookFlowPolicyForm: true } },
  });
  await flushPromises();
  const input = wrapper.get(
    '[data-testid="relationship-rule-health_hysteresis_points"]'
  );
  expect(input.attributes('min')).toBe('0');
  expect(input.attributes('max')).toBe('20');
  await input.setValue('5');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.saveConfiguration).toHaveBeenCalledWith(
    '1400',
    expect.objectContaining({
      version: 7,
      rules: expect.objectContaining({ health_hysteresis_points: 5 }),
    })
  );
  wrapper.unmount();
});
