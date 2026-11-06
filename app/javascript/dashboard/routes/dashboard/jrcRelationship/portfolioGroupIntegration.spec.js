import { mount, shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import messages from 'dashboard/i18n/locale/en/relationship.json';
import Workload from './PortfolioGroupWorkloadPanel.vue';
import Groups from './PortfolioGroupsPanel.vue';
import ModulePage from './ModulePage.vue';
import Layout from './RelationshipLayout.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  replace: vi.fn(),
  api: {
    metadata: vi.fn(),
    portfolio: vi.fn(),
    dashboard: vi.fn(),
    portfolioGroup: vi.fn(),
    portfolioGroupCustomers: vi.fn(),
    portfolioGroupWorkload: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace, push: vi.fn() }),
}));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));
const wrappers = [];
const group = {
  id: 18,
  version: 4,
  name: 'Existing operational portfolio',
  goals: [],
  status: 'active',
  can_manage: false,
};
const metadata = {
  can_manage: false,
  can_team: false,
  can_configure: false,
  pipelines: [],
  owners: [],
  teams: [],
  units: [],
  formatting: {},
};
const list = {
  data: { payload: [], meta: { page: 1, per_page: 25, total: 0 } },
};
const render = (component, props = {}, shallow = false) => {
  const wrapper = (shallow ? shallowMount : mount)(component, {
    props,
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
    },
  });
  wrappers.push(wrapper);
  return wrapper;
};
beforeEach(() => {
  vi.resetAllMocks();
  mocks.route = reactive({
    params: { accountId: '1400' },
    name: 'jrc_relationship_portfolio',
    query: {},
  });
  mocks.store = reactive({
    getters: {
      getCurrentUserID: 7,
      getCurrentRole: 'administrator',
      getCurrentUser: { accounts: [] },
    },
  });
  mocks.replace.mockImplementation(async ({ query }) => {
    mocks.route.query = query;
  });
  mocks.api.metadata.mockResolvedValue({ data: metadata });
  mocks.api.portfolio.mockResolvedValue(list);
  mocks.api.dashboard.mockResolvedValue({ data: { customers: 0 } });
  mocks.api.portfolioGroup.mockResolvedValue({ data: group });
  mocks.api.portfolioGroupCustomers.mockResolvedValue(list);
  mocks.api.portfolioGroupWorkload.mockResolvedValue({
    data: {
      state: 'observed',
      read_only: true,
      measures: [
        { unit: 'customers', state: 'available', value: 1 },
        { unit: 'points', state: 'available', value: 16 },
        { unit: 'hours', state: 'explicit_inputs_missing', value: null },
      ],
    },
  });
});
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

it('shows native observed workload and distinguishes missing hours from zero or spare capacity', async () => {
  const wrapper = render(Workload, { group });
  await flushPromises();
  expect(mocks.api.portfolioGroupWorkload).toHaveBeenCalledWith(
    '1400',
    18,
    expect.objectContaining({ signal: expect.any(AbortSignal) })
  );
  const values = wrapper.findAll('dd').map(row => row.text());
  expect(values).toEqual([
    '1',
    '16',
    'Explicit workload inputs are unavailable.',
  ]);
  expect(wrapper.text()).toContain('global customer capacity stays unique');
  await wrapper.setProps({ group: { ...group, version: 5 } });
  await flushPromises();
  expect(mocks.api.portfolioGroupWorkload).toHaveBeenCalledTimes(2);
});

it('discards old workload and ignores late data after authorization changes', async () => {
  let resolve;
  const wrapper = render(Workload, { group });
  await flushPromises();
  mocks.api.portfolioGroupWorkload.mockReturnValueOnce(
    new Promise(done => {
      resolve = done;
    })
  );
  await wrapper.get('button').trigger('click');
  const signal = mocks.api.portfolioGroupWorkload.mock.calls.at(-1)[2].signal;
  mocks.api.portfolioGroupWorkload.mockResolvedValueOnce({
    data: { state: 'scope_denied', read_only: true, measures: [] },
  });
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  resolve({
    data: {
      state: 'observed',
      measures: [{ unit: 'customers', state: 'available', value: 99 }],
    },
  });
  await flushPromises();
  expect(signal.aborted).toBe(true);
  expect(wrapper.find('dl').exists()).toBe(false);
  expect(wrapper.text()).toContain('Full workload is unavailable');
  expect(wrapper.text()).not.toContain('99');
});

it('clears a previous workload snapshot on denied refresh', async () => {
  const wrapper = render(Workload, { group });
  await flushPromises();
  mocks.api.portfolioGroupWorkload.mockRejectedValue({
    response: { status: 403 },
  });
  await wrapper.get('button').trigger('click');
  await flushPromises();
  expect(wrapper.find('dl').exists()).toBe(false);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
});

it('opens the native scoped customer list and the separate observed workload tab', async () => {
  mocks.route.query = {
    group_id: '18',
    section: 'groups',
    customer_segment_id: '12',
  };
  const wrapper = render(Groups, { metadata }, true);
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(row => row.text() === 'Observed workload')
    .trigger('click');
  expect(wrapper.findComponent(Workload).props('group')).toEqual(group);
  await wrapper
    .findAll('button')
    .find(row => row.text() === 'Open filtered customer list')
    .trigger('click');
  expect(mocks.route.query).toEqual({
    group_id: undefined,
    section: 'customers',
    customer_segment_id: '12',
    portfolio_group_id: 18,
  });
});

it('passes grouping to metrics, native customer lists and pickers, and removes only this filter', async () => {
  mocks.route.query = { portfolio_group_id: '18', customer_segment_id: '12' };
  const wrapper = render(ModulePage, { screen: 'portfolio' }, true);
  await flushPromises();
  expect(mocks.api.dashboard.mock.calls[0][1]).toMatchObject({
    portfolio_group_id: '18',
    customer_segment_id: '12',
  });
  expect(mocks.api.portfolio.mock.calls[0][1]).toMatchObject({
    portfolio_group_id: '18',
    customer_segment_id: '12',
  });
  expect(mocks.api.portfolio.mock.calls[1][1]).toMatchObject({
    portfolio_group_id: '18',
    customer_segment_id: '12',
  });
  await wrapper
    .get('[data-testid="active-portfolio-group-filter"] button')
    .trigger('click');
  await flushPromises();
  expect(mocks.route.query.customer_segment_id).toBe('12');
  expect(
    mocks.api.dashboard.mock.calls.at(-1)[1].portfolio_group_id
  ).toBeUndefined();
  expect(
    wrapper.find('[data-testid="active-portfolio-group-filter"]').exists()
  ).toBe(false);
});

it('keeps grouping on operational navigation and excludes it from settings', async () => {
  mocks.api.metadata.mockResolvedValue({
    data: { ...metadata, can_configure: true },
  });
  mocks.route.query = { portfolio_group_id: '18' };
  const wrapper = render(Layout, {}, true);
  await flushPromises();
  const tabs = wrapper
    .findAllComponents({ name: 'ModuleTabs' })[0]
    .props('items');
  expect(tabs.find(row => row.key === 'portfolio').to.query).toEqual({
    portfolio_group_id: '18',
  });
  expect(tabs.find(row => row.key === 'settings').to.query).toEqual({});
});

it('reloads and clears grouped operational data when the current role is revoked', async () => {
  mocks.route.query = { portfolio_group_id: '18' };
  const wrapper = render(ModulePage, { screen: 'portfolio' }, true);
  await flushPromises();
  mocks.api.metadata.mockRejectedValue({ response: { status: 403 } });
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  expect(mocks.api.metadata).toHaveBeenCalledTimes(2);
  expect(wrapper.findComponent({ name: 'PortfolioTable' }).exists()).toBe(
    false
  );
});
