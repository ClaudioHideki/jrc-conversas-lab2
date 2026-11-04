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
