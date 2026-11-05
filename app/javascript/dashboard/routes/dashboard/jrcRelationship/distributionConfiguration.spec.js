import { mount, flushPromises } from '@vue/test-utils';
import { beforeEach, expect, it, vi } from 'vitest';
import Panel from './ConfigurationPanel.vue';
const api = vi.hoisted(() => ({
  configuration: vi.fn(),
  saveConfiguration: vi.fn(),
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: api }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '12' } }),
}));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentUserID: 7 } }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const configuration = {
  version: 1,
  scope_key: 'account',
  weights: { relationship: 100 },
  history: [],
  rules: {
    portfolio_capacity_limits: [],
    portfolio_transfer_approval_required: false,
    portfolio_review_validity_minutes: 15,
    healthy_threshold: 80,
    required_documents: [],
  },
};
beforeEach(() => {
  vi.clearAllMocks();
  api.configuration.mockImplementation((_, options) =>
    Promise.resolve({
      data: {
        ...structuredClone(configuration),
        scope_key: options.params.scope_key,
      },
    })
  );
  api.saveConfiguration.mockResolvedValue({ data: {} });
});
const mountPanel = () =>
  mount(Panel, {
    props: {
      allowed: true,
      metadata: {
        owners: [[7, 'Synthetic analyst']],
        configuration_teams: [[22, 'Native team']],
      },
    },
    global: { stubs: { OperationsSettingsPanel: true } },
  });

it('edits and persists customer capacity as typed native configuration, not a comma-separated string', async () => {
  const wrapper = mountPanel();
  await flushPromises();
  const capacity = wrapper.find('fieldset');
  await capacity.get('button').trigger('click');
  await capacity.findAll('input')[0].setValue('10');
  await capacity.findAll('input')[1].setValue('50');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(api.saveConfiguration).toHaveBeenCalledWith(
    '12',
    expect.objectContaining({
      rules: expect.objectContaining({
        portfolio_capacity_limits: [
          { user_id: 7, maximum: 10, availability: 0.5, dedication: 1 },
        ],
      }),
    })
  );
  wrapper.unmount();
});

it('offers native team settings without presenting health controls that do not resolve by team', async () => {
  const wrapper = mountPanel();
  await flushPromises();
  await wrapper.findAll('select')[0].setValue('team:22');
  await flushPromises();
  expect(api.configuration).toHaveBeenLastCalledWith('12', {
    params: { scope_key: 'team:22' },
  });
  expect(wrapper.text()).not.toContain('RELATIONSHIP.WEIGHTS');
  expect(
    wrapper.find('[data-testid="relationship-rule-healthy_threshold"]').exists()
  ).toBe(false);
  expect(wrapper.find('fieldset').exists()).toBe(true);
  wrapper.unmount();
});
