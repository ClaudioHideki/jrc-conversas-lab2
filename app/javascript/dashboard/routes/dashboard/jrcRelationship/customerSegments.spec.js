import { shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import AnalystWorkspace from './AnalystWorkspace.vue';
import ModulePage from './ModulePage.vue';
import CustomerWorkspace from './CustomerWorkspace.vue';
import TeamPanel from './TeamPanel.vue';
import HandoffPanel from './HandoffPanel.vue';
import RelationshipLayout from './RelationshipLayout.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: {
    metadata: vi.fn(),
    dashboard: vi.fn(),
    records: vi.fn(),
    portfolio: vi.fn(),
    handoffs: vi.fn(),
    team: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
}));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));
const mount = (component, props = {}) =>
  shallowMount(component, {
    props,
    global: { stubs: { RouterLink: { template: '<a><slot /></a>' } } },
  });
beforeEach(() => {
  mocks.route = reactive({
    params: { accountId: '1' },
    name: 'jrc_relationship_portfolio',
    query: { customer_segment_id: '12', segment_id: '5' },
  });
  mocks.store = { getters: reactive({ getCurrentUserID: 7 }) };
  mocks.api.metadata.mockResolvedValue({
    data: {
      can_manage: false,
      can_team: false,
      can_configure: true,
      pipelines: [],
      owners: [],
      teams: [],
      units: [],
      formatting: {},
    },
  });
  mocks.api.dashboard.mockResolvedValue({
    data: { customers: 0, priority_actions: [] },
  });
  const list = {
    data: { payload: [], meta: { page: 1, total: 0, per_page: 25 } },
  };
  ['portfolio', 'records', 'handoffs', 'team'].forEach(key =>
    mocks.api[key].mockResolvedValue(list)
  );
});

it('keeps the published segment in operational tabs and omits it from configuration', async () => {
  const wrapper = mount(RelationshipLayout);
  await flushPromises();
  expect(
    wrapper
      .findComponent({ name: 'ModuleSegmentFilter' })
      .attributes('modulekey')
  ).toBe('relationship');
  const items = wrapper
    .findAllComponents({ name: 'ModuleTabs' })[0]
    .props('items');
  expect(items.find(item => item.key === 'portfolio').to.query).toEqual({
    customer_segment_id: '12',
  });
  expect(items.find(item => item.key === 'settings').to.query).toEqual({});
  wrapper.unmount();
});

it('reloads analyst dashboard and action lists when the selected segment changes', async () => {
  const wrapper = mount(AnalystWorkspace, { screen: 'overview' });
  await flushPromises();
  expect(mocks.api.dashboard).toHaveBeenCalledWith(
    '1',
    expect.objectContaining({ customer_segment_id: '12' }),
    expect.anything()
  );
  mocks.route.query.customer_segment_id = '19';
  await wrapper.setProps({ screen: 'actions' });
  await flushPromises();
  expect(mocks.api.records).toHaveBeenLastCalledWith(
    '1',
    'actions',
    expect.objectContaining({ customer_segment_id: '19', page: 1 }),
    expect.anything()
  );
  wrapper.unmount();
});

it('combines the existing classification with the published segment in portfolio and customer options', async () => {
  const wrapper = mount(ModulePage, { screen: 'portfolio' });
  await flushPromises();
  expect(mocks.api.dashboard).toHaveBeenCalledWith(
    '1',
    expect.objectContaining({ customer_segment_id: '12', segment_id: '5' }),
    expect.anything()
  );
  expect(mocks.api.portfolio).toHaveBeenCalledWith(
    '1',
    expect.objectContaining({ customer_segment_id: '12', per_page: 50 }),
    expect.anything()
  );
  delete mocks.route.query.customer_segment_id;
  await flushPromises();
  expect(mocks.api.portfolio).toHaveBeenLastCalledWith(
    '1',
    expect.objectContaining({ customer_segment_id: undefined, per_page: 50 }),
    expect.anything()
  );
  wrapper.unmount();
});

it('uses the selected cohort for the customer workspace and clears the old page on native filter navigation', async () => {
  mocks.route.query.page = '2';
  const wrapper = mount(CustomerWorkspace);
  await flushPromises();
  expect(mocks.api.portfolio).toHaveBeenCalledWith(
    '1',
    expect.objectContaining({ customer_segment_id: '12', page: '2' }),
    expect.anything()
  );
  mocks.route.query = { customer_segment_id: '19' };
  await flushPromises();
  expect(mocks.api.portfolio).toHaveBeenLastCalledWith(
    '1',
    expect.objectContaining({ customer_segment_id: '19', page: 1 }),
    expect.anything()
  );
  wrapper.unmount();
});

it('uses the same cohort for team indicators and handoff/customer choices', async () => {
  const team = mount(TeamPanel);
  const handoffs = mount(HandoffPanel, { allowed: true });
  await flushPromises();
  expect(mocks.api.team).toHaveBeenCalledWith(
    '1',
    expect.objectContaining({ customer_segment_id: '12' }),
    expect.anything()
  );
  expect(mocks.api.handoffs).toHaveBeenCalledWith(
    '1',
    expect.objectContaining({ params: { customer_segment_id: '12' } })
  );
  mocks.route.query.customer_segment_id = '19';
  await flushPromises();
  expect(mocks.api.team).toHaveBeenLastCalledWith(
    '1',
    expect.objectContaining({ customer_segment_id: '19' }),
    expect.anything()
  );
  expect(mocks.api.handoffs).toHaveBeenLastCalledWith(
    '1',
    expect.objectContaining({ params: { customer_segment_id: '19' } })
  );
  team.unmount();
  handoffs.unmount();
});
