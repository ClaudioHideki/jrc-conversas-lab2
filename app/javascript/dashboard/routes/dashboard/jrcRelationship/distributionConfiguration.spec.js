import { mount, flushPromises } from '@vue/test-utils';
import { beforeEach, expect, it, vi } from 'vitest';
import Panel from './ConfigurationPanel.vue';
import PriorityBandsForm from './PriorityBandsForm.vue';
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
    automatic_action_cooldown_hours: 0,
    automatic_action_daily_limit: 0,
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

it('prevents a malformed numeric band policy from reaching save and persists explicit typed limits with the native configuration version', async () => {
  const wrapper = mountPanel();
  await flushPromises();
  const form = wrapper.findComponent(PriorityBandsForm);
  expect(form.exists()).toBe(true);
  await form.get('input[type="checkbox"]').setValue(true);
  await wrapper.get('form').trigger('submit');
  expect(api.saveConfiguration).not.toHaveBeenCalled();
  await [90, 80, 60, 0].reduce(async (previous, minimum, index) => {
    await previous;
    await form.findAll('input[type="number"]')[index].setValue(minimum);
  }, Promise.resolve());
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(api.saveConfiguration).toHaveBeenCalledWith(
    '12',
    expect.objectContaining({
      version: 1,
      rules: expect.objectContaining({
        priority_bands: [
          { code: 'P0', minimum: 90 },
          { code: 'P1', minimum: 80 },
          { code: 'P2', minimum: 60 },
          { code: 'P3', minimum: 0 },
        ],
      }),
    })
  );
  wrapper.unmount();
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
  expect(
    wrapper
      .find('[data-testid="relationship-rule-automatic_action_cooldown_hours"]')
      .exists()
  ).toBe(false);
  wrapper.unmount();
});

it('allows zero and persists typed cooldown hours through the existing permission-bound settings form', async () => {
  const wrapper = mountPanel();
  await flushPromises();
  const input = wrapper.get(
    '[data-testid="relationship-rule-automatic_action_cooldown_hours"]'
  );
  expect(input.attributes('min')).toBe('0');
  expect(input.attributes('max')).toBe('8760');
  await input.setValue('72');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(api.saveConfiguration).toHaveBeenCalledWith(
    '12',
    expect.objectContaining({
      rules: expect.objectContaining({ automatic_action_cooldown_hours: 72 }),
    })
  );
  wrapper.unmount();
});

it('edits the global daily monitoring ceiling as an integer only in account settings', async () => {
  const wrapper = mountPanel();
  await flushPromises();
  const input = wrapper.get(
    '[data-testid="relationship-rule-automatic_action_daily_limit"]'
  );
  expect(input.attributes('min')).toBe('0');
  expect(input.attributes('step')).toBe('1');
  await input.setValue('8');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(api.saveConfiguration).toHaveBeenCalledWith(
    '12',
    expect.objectContaining({
      rules: expect.objectContaining({ automatic_action_daily_limit: 8 }),
    })
  );
  await wrapper.findAll('select')[0].setValue('team:22');
  await flushPromises();
  expect(
    wrapper
      .find('[data-testid="relationship-rule-automatic_action_daily_limit"]')
      .exists()
  ).toBe(false);
  wrapper.unmount();
});
