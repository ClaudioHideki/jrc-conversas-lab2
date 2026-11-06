import { mount, shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import messages from 'dashboard/i18n/locale/en/relationship.json';
import Rules from './PortfolioGroupRulesPanel.vue';
import Capacity from './PortfolioCapacityLimitsForm.vue';
import Groups from './PortfolioGroupsPanel.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  configuration: vi.fn(),
  saveConfiguration: vi.fn(),
  portfolioGroup: vi.fn(),
  portfolioGroupCustomers: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: vi.fn() }),
}));
vi.mock('vuex', () => ({ useStore: () => mocks.store }));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks }));
vi.mock('./CustomerPanel.vue', () => ({
  default: { name: 'CustomerPanel', template: '<div />' },
}));
const group = { id: 18, version: 4, can_configure: true };
const metadata = { owners: [[7, 'Native analyst']] };
const initial = () => ({
  scope_key: 'portfolio:18',
  version: 2,
  portfolio_revision: 4,
  weights: {
    adoption: 25,
    relationship: 15,
    service_desk: 15,
    finance: 15,
    satisfaction: 10,
    contract: 10,
    projects: 5,
    engagement: 5,
    sentiment: 0,
  },
  rules: {
    portfolio_capacity_limits: [
      { user_id: 7, maximum: 10, availability: 1, dedication: 1 },
    ],
    portfolio_transfer_approval_required: false,
    portfolio_review_validity_minutes: 15,
  },
  history: [],
});
const wrappers = [];
const render = () => {
  const wrapper = mount(Rules, {
    props: { group, metadata },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
    },
  });
  wrappers.push(wrapper);
  return wrapper;
};
const button = (wrapper, text) =>
  wrapper.findAll('button').find(row => row.text() === text);
beforeEach(() => {
  vi.resetAllMocks();
  mocks.route = reactive({ params: { accountId: '1400' } });
  mocks.store = reactive({
    getters: {
      getCurrentUserID: 7,
      getCurrentRole: 'administrator',
      getCurrentUser: { accounts: [] },
    },
  });
  mocks.configuration.mockImplementation(async () => ({ data: initial() }));
  mocks.portfolioGroup.mockResolvedValue({ data: group });
  mocks.portfolioGroupCustomers.mockResolvedValue({
    data: { payload: [], meta: { page: 1, per_page: 25, total: 0 } },
  });
  mocks.saveConfiguration.mockImplementation(async (_, fields) => ({
    data: { ...fields, version: fields.version + 1, history: [] },
  }));
});
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

it('reuses native capacity controls and reviews exact configuration and group revisions before persistence', async () => {
  const wrapper = render();
  await flushPromises();
  expect(mocks.configuration).toHaveBeenCalledWith(
    '1400',
    expect.objectContaining({
      params: { scope_key: 'portfolio:18' },
      signal: expect.any(AbortSignal),
    })
  );
  await wrapper.get('input[type="number"]').setValue('20');
  await button(wrapper, 'Transfer rules').trigger('click');
  await wrapper.get('input[type="checkbox"]').setValue(true);
  await wrapper
    .findAll('fieldset')
    .at(-1)
    .get('input[type="number"]')
    .setValue('0.5');
  await wrapper.get('form').trigger('submit');
  expect(mocks.saveConfiguration).not.toHaveBeenCalled();
  expect(wrapper.findComponent(Capacity).props('disabled')).toBe(true);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  const fields = mocks.saveConfiguration.mock.calls[0][1];
  expect(fields).toMatchObject({
    scope_key: 'portfolio:18',
    version: 2,
    portfolio_revision: 4,
    rules: {
      portfolio_transfer_approval_required: true,
      portfolio_review_validity_minutes: 0.5,
      portfolio_capacity_limits: [
        { user_id: 7, maximum: 20, availability: 1, dedication: 1 },
      ],
    },
  });
  expect(fields.weights).toEqual(initial().weights);
  expect(wrapper.text()).toContain('Versioned portfolio rules saved');
});

it('retains the edited capacity and captured revisions on conflict and requires explicit reload', async () => {
  mocks.saveConfiguration.mockRejectedValue({
    response: { status: 409, data: { errors: ['Grouping changed'] } },
  });
  const wrapper = render();
  await flushPromises();
  await wrapper.get('input[type="number"]').setValue('25');
  await wrapper.get('form').trigger('submit');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.findComponent(Capacity).props('modelValue')[0].maximum).toBe(
    25
  );
  expect(wrapper.get('button[type="submit"]').element.disabled).toBe(true);
  expect(mocks.saveConfiguration.mock.calls[0][1]).toMatchObject({
    version: 2,
    portfolio_revision: 4,
  });
  await wrapper.get('form').trigger('submit');
  expect(mocks.saveConfiguration).toHaveBeenCalledTimes(1);
  await button(
    wrapper,
    'Reload the current version and discard this draft'
  ).trigger('click');
  await flushPromises();
  expect(wrapper.findComponent(Capacity).props('modelValue')[0].maximum).toBe(
    10
  );
});

it('does not confirm an HTTP 200 without the exact saved scope and revisions', async () => {
  mocks.saveConfiguration.mockResolvedValue({
    data: { scope_key: 'account', version: 3, portfolio_revision: 4 },
  });
  const wrapper = render();
  await flushPromises();
  await wrapper.get('form').trigger('submit');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.text()).not.toContain('Versioned portfolio rules saved');
  expect(wrapper.get('[role="alert"]').text()).toContain(
    'could not be confirmed'
  );
});

it('clears loaded rules and rejects late mutation feedback after a role change', async () => {
  let resolve;
  mocks.saveConfiguration.mockReturnValue(
    new Promise(done => {
      resolve = done;
    })
  );
  const wrapper = render();
  await flushPromises();
  await wrapper.get('form').trigger('submit');
  await wrapper.get('form').trigger('submit');
  mocks.configuration.mockRejectedValue({ response: { status: 403 } });
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  resolve({ data: { ...initial(), version: 3 } });
  await flushPromises();
  expect(wrapper.find('form').exists()).toBe(false);
  expect(wrapper.text()).not.toContain('Versioned portfolio rules saved');
});

it('blocks saving when native capacity is invalid or configuration authority is removed', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.get('input[type="number"]').setValue('-1');
  expect(wrapper.get('button[type="submit"]').element.disabled).toBe(true);
  await wrapper.get('form').trigger('submit');
  expect(mocks.saveConfiguration).not.toHaveBeenCalled();
  await wrapper.setProps({ group: { ...group, can_configure: false } });
  await flushPromises();
  expect(wrapper.find('form').exists()).toBe(false);
  expect(mocks.configuration).toHaveBeenCalledTimes(1);
});

it('clears the saved confirmation when a new draft changes the previously persisted rules', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.get('form').trigger('submit');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.text()).toContain('Versioned portfolio rules saved');
  await button(wrapper, 'Capacity limits').trigger('click');
  await wrapper.get('input[type="number"]').setValue('30');
  expect(wrapper.text()).not.toContain('Versioned portfolio rules saved');
});

it('wires rules to the selected group and removes the editor when record-specific configuration access is revoked', async () => {
  mocks.route.query = { group_id: '18' };
  const wrapper = shallowMount(Groups, {
    props: { metadata },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
    },
  });
  wrappers.push(wrapper);
  await flushPromises();
  await button(wrapper, 'Capacity and transfer rules').trigger('click');
  expect(wrapper.findComponent(Rules).props('group')).toEqual(group);
  mocks.portfolioGroup.mockResolvedValue({
    data: { ...group, can_configure: false },
  });
  await button(wrapper, 'Refresh').trigger('click');
  await flushPromises();
  expect(wrapper.findComponent(Rules).exists()).toBe(false);
  expect(button(wrapper, 'Capacity and transfer rules')).toBeUndefined();
  expect(wrapper.text()).toContain(
    'No authorized customers are linked to this portfolio.'
  );
});
