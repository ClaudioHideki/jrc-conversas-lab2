import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import Panel from './TeamPanel.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  getters: null,
  metadata: vi.fn(),
  team: vi.fn(),
  dashboard: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcRelationship', () => ({
  default: {
    metadata: mocks.metadata,
    team: mocks.team,
    dashboard: mocks.dashboard,
  },
}));
const render = () =>
  mount(Panel, {
    global: {
      stubs: {
        MetricsPanel: true,
        MetricDrilldownPanel: true,
        WithdrawalReadinessDialog: true,
        AnalystCapacityDialog: true,
      },
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: 1 }, query: {} });
  mocks.getters = reactive({
    getCurrentUserID: 3,
    getCurrentRole: 'administrator',
    getCurrentUser: { accounts: [] },
  });
  mocks.metadata.mockResolvedValue({
    data: { owners: [[7, 'Synthetic analyst']] },
  });
  mocks.team.mockResolvedValue({ data: { payload: [] } });
  mocks.dashboard.mockResolvedValue({ data: {} });
});

it('keeps the readiness entry available after the analyst has no remaining allocated customers', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.get('[data-testid="withdrawal-analyst"]').setValue('7');
  await wrapper.get('[data-testid="withdrawal-entry"]').trigger('submit');
  const dialog = wrapper.findComponent({ name: 'WithdrawalReadinessDialog' });
  expect(dialog.exists()).toBe(true);
  expect(dialog.props('analystId')).toBe(7);
  wrapper.unmount();
});

it('opens current capacity without allocated rows and closes it on a role change without submitting withdrawal', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.get('[data-testid="withdrawal-analyst"]').setValue('7');
  await wrapper.get('[data-testid="analyst-capacity-open"]').trigger('click');
  expect(
    wrapper.findComponent({ name: 'AnalystCapacityDialog' }).props('analystId')
  ).toBe(7);
  expect(
    wrapper.findComponent({ name: 'WithdrawalReadinessDialog' }).exists()
  ).toBe(false);
  mocks.getters.getCurrentRole = 'agent';
  await flushPromises();
  expect(
    wrapper.findComponent({ name: 'AnalystCapacityDialog' }).exists()
  ).toBe(false);
  wrapper.unmount();
});
it('removes cached readiness/owner options and reloads native metadata on a role change', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.get('[data-testid="withdrawal-analyst"]').setValue('7');
  await wrapper.get('[data-testid="withdrawal-entry"]').trigger('submit');
  mocks.metadata.mockRejectedValue({ response: { status: 403 } });
  mocks.getters.getCurrentRole = 'agent';
  await flushPromises();
  expect(
    wrapper.findComponent({ name: 'WithdrawalReadinessDialog' }).exists()
  ).toBe(false);
  expect(wrapper.text()).not.toContain('Synthetic analyst');
  expect(mocks.metadata).toHaveBeenCalledTimes(2);
  wrapper.unmount();
});
