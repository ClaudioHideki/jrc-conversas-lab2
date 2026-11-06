import { mount, shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import messages from 'dashboard/i18n/locale/en/relationship.json';
import Editor from './PortfolioGroupEditor.vue';
import CustomersDialog from './PortfolioGroupCustomersDialog.vue';
import Panel from './PortfolioGroupsPanel.vue';
import Workspace from './PortfolioWorkspace.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  replace: vi.fn(),
  api: {
    metadata: vi.fn(),
    portfolio: vi.fn(),
    portfolioGroups: vi.fn(),
    portfolioGroup: vi.fn(),
    portfolioGroupCustomers: vi.fn(),
    savePortfolioGroup: vi.fn(),
    savePortfolioGroupCustomers: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('vuex', () => ({ useStore: () => mocks.store }));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));
vi.mock('./CustomerPanel.vue', () => ({
  default: { name: 'CustomerPanel', template: '<div />' },
}));
const Dialog = {
  setup(_, { expose }) {
    expose({ open: vi.fn() });
  },
  template: '<section><slot /></section>',
};
const metadata = {
  can_manage: true,
  can_team: true,
  can_configure: true,
  owners: [[7, 'Existing coordinator']],
  teams: [],
  units: [],
  segments: [],
};
const record = {
  id: 18,
  name: 'Existing portfolio',
  objective: 'Measured coverage',
  owner_id: 7,
  owner_name: 'Existing coordinator',
  visibility: 'private',
  status: 'active',
  version: 4,
  goals: [],
  can_manage: true,
  can_configure: true,
  customer_count: 1,
};
const wrappers = [];
const render = (component, props, shallow = false) => {
  const wrapper = (shallow ? shallowMount : mount)(component, {
    props,
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
      stubs: { Dialog },
    },
  });
  wrappers.push(wrapper);
  return wrapper;
};
const button = (wrapper, text) =>
  wrapper.findAll('button').find(row => row.text() === text);
const page = (payload, number = 1, total = payload.length) => ({
  data: { payload, meta: { page: number, total, per_page: 25 } },
});
beforeEach(() => {
  vi.resetAllMocks();
  mocks.route = reactive({ params: { accountId: '1400' }, query: {} });
  mocks.store = reactive({
    getters: {
      getCurrentUserID: 7,
      getCurrentRole: 'administrator',
      getCurrentUser: { accounts: [{ id: 1400, role: 'administrator' }] },
    },
  });
  mocks.replace.mockImplementation(async ({ query }) => {
    mocks.route.query = query;
  });
  mocks.api.portfolioGroups.mockResolvedValue(page([record]));
  mocks.api.metadata.mockResolvedValue({ data: metadata });
  mocks.api.portfolioGroup.mockResolvedValue({ data: record });
  mocks.api.portfolioGroupCustomers.mockResolvedValue(
    page([{ id: 31, name: 'Existing customer', status: 'active' }])
  );
  mocks.api.portfolio.mockResolvedValue(
    page([{ id: 31, name: 'Existing customer' }], 1, 26)
  );
});
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
});

it('reviews typed goals individually and preserves every goal before emitting the creation payload', async () => {
  const wrapper = render(Editor, { metadata });
  await wrapper
    .get('[data-testid="portfolio-group-name"]')
    .setValue('Product coverage');
  await button(wrapper, 'Goals').trigger('click');
  await button(wrapper, 'Add goal').trigger('click');
  await wrapper.get('fieldset input').setValue('Coverage');
  await wrapper.findAll('input[type="number"]')[1].setValue('80');
  await button(wrapper, 'Add goal').trigger('click');
  await wrapper.get('fieldset input').setValue('Renewals');
  await wrapper.findAll('input[type="number"]')[1].setValue('25');
  await wrapper.get('select').setValue('0');
  expect(wrapper.get('fieldset input').element.value).toBe('Coverage');
  expect(wrapper.findAll('input[type="number"]')[1].element.value).toBe('80');
  await button(wrapper, 'Review').trigger('click');
  expect(wrapper.text()).toContain('Coverage');
  expect(wrapper.text()).toContain('Renewals');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0]).toEqual({
    portfolio_group: {
      name: 'Product coverage',
      objective: '',
      owner_id: 7,
      team_id: null,
      business_unit_id: null,
      segment_id: null,
      status: 'active',
      visibility: 'private',
      goals: [
        { metric: 'Coverage', target: 80, unit: '' },
        { metric: 'Renewals', target: 25, unit: '' },
      ],
    },
    expected_version: undefined,
    reason: '',
  });
});

it('keeps the reviewed revision and draft on conflict without silently rebasing or retrying', async () => {
  const wrapper = render(Editor, { metadata, record });
  await wrapper
    .get('[data-testid="portfolio-group-name"]')
    .setValue('Edited draft');
  await wrapper.setProps({ record: { ...record, version: 99 } });
  await button(wrapper, 'Review').trigger('click');
  await wrapper.get('textarea').setValue('Explicit operational review');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0].expected_version).toBe(4);
  await wrapper.setProps({ conflict: true, error: 'Stale revision' });
  expect(wrapper.get('button[type="submit"]').element.disabled).toBe(true);
  expect(wrapper.text()).toContain('Edited draft');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')).toHaveLength(1);
  await button(
    wrapper,
    'Reload the current version and discard this draft'
  ).trigger('click');
  expect(wrapper.emitted('reload')).toHaveLength(1);
});

it('preserves the current coordinator option outside the current selectable roster', async () => {
  const wrapper = render(Editor, {
    metadata: { ...metadata, owners: [], can_configure: false },
    record,
  });
  await button(wrapper, 'Team and access').trigger('click');
  expect(wrapper.get('option[value="7"]').text()).toBe('Existing coordinator');
  expect(wrapper.findAll('select')[1].element.disabled).toBe(true);
  expect(wrapper.findAll('select')[2].element.disabled).toBe(true);
});

it('reviews native customer selections across pages without changing source ownership', async () => {
  mocks.api.portfolio
    .mockResolvedValueOnce(page([{ id: 31, name: 'First customer' }], 1, 26))
    .mockResolvedValueOnce(page([{ id: 32, name: 'Second customer' }], 2, 26));
  const wrapper = render(CustomersDialog, {
    group: { ...record, business_unit_id: 9 },
  });
  await flushPromises();
  expect(mocks.api.portfolio.mock.calls[0][1].business_unit_id).toBe(9);
  await wrapper.get('input[type="checkbox"]').setValue(true);
  await button(wrapper, 'Next page').trigger('click');
  await flushPromises();
  await wrapper.get('input[type="checkbox"]').setValue(true);
  await button(wrapper, 'Review selected customers').trigger('click');
  expect(wrapper.text()).toContain('First customer');
  expect(wrapper.text()).toContain('Second customer');
  await wrapper.get('textarea').setValue('Confirmed existing customer links');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0]).toEqual({
    assignment_ids: [31, 32],
    active: true,
    expected_version: 4,
    reason: 'Confirmed existing customer links',
  });
  expect(mocks.api.savePortfolioGroupCustomers).not.toHaveBeenCalled();
});

it('only deactivates the reviewed group link and preserves its original revision', async () => {
  const wrapper = render(CustomersDialog, {
    group: record,
    customer: { id: 31, name: 'Existing customer' },
  });
  await wrapper.setProps({ group: { ...record, version: 99 } });
  await wrapper.get('textarea').setValue('Reviewed link deactivation');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0]).toEqual({
    assignment_ids: [31],
    active: false,
    expected_version: 4,
    reason: 'Reviewed link deactivation',
  });
  expect(mocks.api.portfolio).not.toHaveBeenCalled();
});

it('discards pending picker results and selections after a role change', async () => {
  let resolve;
  mocks.api.portfolio.mockReturnValue(
    new Promise(done => {
      resolve = done;
    })
  );
  const wrapper = render(CustomersDialog, { group: record });
  const signal = mocks.api.portfolio.mock.calls[0][2].signal;
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  resolve(page([{ id: 99, name: 'Previous privileged customer' }]));
  await flushPromises();
  expect(signal.aborted).toBe(true);
  expect(wrapper.emitted('close')).toHaveLength(1);
  expect(wrapper.text()).not.toContain('Previous privileged customer');
});

it('searches, paginates and clears native group filters', async () => {
  mocks.api.portfolioGroups.mockResolvedValue(page([record], 1, 26));
  const wrapper = render(Panel, { metadata }, true);
  await flushPromises();
  await button(wrapper, 'Next page').trigger('click');
  await flushPromises();
  expect(mocks.api.portfolioGroups.mock.calls.at(-1)[1].page).toBe(2);
  await wrapper.get('input').setValue('Coverage');
  await wrapper.get('select').setValue('archived');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.api.portfolioGroups.mock.calls.at(-1)[1]).toEqual({
    page: 1,
    q: 'Coverage',
    status: 'archived',
  });
  await button(wrapper, 'Clear filters').trigger('click');
  await flushPromises();
  expect(mocks.api.portfolioGroups.mock.calls.at(-1)[1]).toEqual({
    page: 1,
    q: '',
    status: 'active',
  });
});

it('saves an actual reviewed creation receipt, navigates to its fresh detail and reloads linked customers', async () => {
  mocks.api.savePortfolioGroup.mockResolvedValue({
    data: { id: 18, version: 0 },
  });
  const wrapper = render(Panel, { metadata }, true);
  await flushPromises();
  await button(wrapper, 'New portfolio').trigger('click');
  const fields = { portfolio_group: { name: 'Reviewed creation' } };
  wrapper.findComponent(Editor).vm.$emit('save', fields);
  await flushPromises();
  expect(mocks.api.savePortfolioGroup).toHaveBeenCalledWith(
    '1400',
    fields,
    undefined
  );
  expect(mocks.route.query.group_id).toBe(18);
  expect(mocks.api.portfolioGroup).toHaveBeenCalledWith(
    '1400',
    18,
    expect.any(Object)
  );
  expect(wrapper.text()).toContain('Existing customer');
  expect(wrapper.text()).toContain('Portfolio changes saved');
});

it('does not report an HTTP 200 with no saved receipt as success', async () => {
  mocks.api.savePortfolioGroup.mockResolvedValue({ data: {} });
  const wrapper = render(Panel, { metadata }, true);
  await flushPromises();
  await button(wrapper, 'New portfolio').trigger('click');
  wrapper
    .findComponent(Editor)
    .vm.$emit('save', { portfolio_group: { name: 'Unconfirmed' } });
  await flushPromises();
  expect(wrapper.findComponent(Editor).props('error')).toContain(
    'could not be confirmed'
  );
  expect(wrapper.text()).not.toContain('Portfolio changes saved');
  expect(mocks.replace).not.toHaveBeenCalled();
});

it('retains an edit draft on HTTP 409 and does not automatically retry the mutation', async () => {
  mocks.route.query.group_id = '18';
  mocks.api.savePortfolioGroup.mockRejectedValue({
    response: { status: 409, data: { errors: ['Stale revision'] } },
  });
  const wrapper = render(Panel, { metadata }, true);
  await flushPromises();
  await button(wrapper, 'Edit portfolio').trigger('click');
  wrapper.findComponent(Editor).vm.$emit('save', {
    portfolio_group: { name: 'Keep draft' },
    expected_version: 4,
  });
  await flushPromises();
  expect(wrapper.findComponent(Editor).props('conflict')).toBe(true);
  expect(wrapper.findComponent(Editor).props('record').version).toBe(4);
  expect(mocks.api.savePortfolioGroup).toHaveBeenCalledTimes(1);
  expect(wrapper.text()).not.toContain('Portfolio changes saved');
});

it('uses record-specific write permissions even when global management is allowed', async () => {
  mocks.route.query.group_id = '18';
  mocks.api.portfolioGroup.mockResolvedValue({
    data: { ...record, can_manage: false, can_configure: false },
  });
  const wrapper = render(Panel, { metadata }, true);
  await flushPromises();
  expect(button(wrapper, 'Edit portfolio')).toBeUndefined();
  expect(button(wrapper, 'Add existing customers')).toBeUndefined();
  expect(button(wrapper, 'Deactivate customer link')).toBeUndefined();
  expect(wrapper.text()).toContain('Existing customer');
});

it('ignores a mutation response after unmount without navigating the next workspace', async () => {
  let resolve;
  mocks.api.savePortfolioGroup.mockReturnValue(
    new Promise(done => {
      resolve = done;
    })
  );
  const wrapper = render(Panel, { metadata }, true);
  await flushPromises();
  await button(wrapper, 'New portfolio').trigger('click');
  wrapper
    .findComponent(Editor)
    .vm.$emit('save', { portfolio_group: { name: 'Old workspace' } });
  wrapper.unmount();
  resolve({ data: { id: 18, version: 0 } });
  await flushPromises();
  expect(mocks.replace).not.toHaveBeenCalled();
});

it('clears private details and ignores late writes when the account changes', async () => {
  let resolve;
  mocks.route.query.group_id = '18';
  mocks.api.savePortfolioGroup.mockReturnValue(
    new Promise(done => {
      resolve = done;
    })
  );
  const wrapper = render(Panel, { metadata }, true);
  await flushPromises();
  await button(wrapper, 'Edit portfolio').trigger('click');
  wrapper
    .findComponent(Editor)
    .vm.$emit('save', { portfolio_group: { name: 'Old account draft' } });
  mocks.api.portfolioGroup.mockRejectedValue({ response: { status: 404 } });
  mocks.route.params.accountId = '1500';
  await flushPromises();
  resolve({ data: { id: 18, version: 5 } });
  await flushPromises();
  expect(wrapper.findComponent(Editor).exists()).toBe(false);
  expect(wrapper.text()).not.toContain('Existing portfolio');
  expect(wrapper.text()).not.toContain('Existing customer');
  expect(wrapper.text()).not.toContain('Portfolio changes saved');
  expect(mocks.replace).not.toHaveBeenCalled();
});

it('limits each reviewed customer batch to fifty existing allocations', async () => {
  mocks.api.portfolio.mockResolvedValue(
    page(
      Array.from({ length: 51 }, (_, index) => ({
        id: index + 1,
        name: `Existing customer ${index + 1}`,
      }))
    )
  );
  const wrapper = render(CustomersDialog, { group: record });
  await flushPromises();
  const checkboxes = wrapper.findAll('input[type="checkbox"]');
  await Promise.all(
    checkboxes.slice(0, 50).map(checkbox => checkbox.setValue(true))
  );
  expect(checkboxes[50].element.disabled).toBe(true);
  await checkboxes[0].setValue(false);
  expect(checkboxes[50].element.disabled).toBe(false);
  await checkboxes[50].setValue(true);
  await button(wrapper, 'Review selected customers').trigger('click');
  await wrapper.get('textarea').setValue('Review bounded native selection');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0].assignment_ids).toHaveLength(50);
  expect(wrapper.emitted('save')[0][0].assignment_ids).toContain(51);
});

it('persists the reviewed link batch through its scoped API and reloads the detail revision', async () => {
  mocks.route.query.group_id = '18';
  mocks.api.savePortfolioGroupCustomers.mockResolvedValue({
    data: {
      id: 18,
      version: 5,
      results: [{ assignment_id: 31, state: 'linked' }],
    },
  });
  const wrapper = render(Panel, { metadata }, true);
  await flushPromises();
  await button(wrapper, 'Add existing customers').trigger('click');
  mocks.api.portfolioGroup.mockResolvedValue({
    data: { ...record, version: 5 },
  });
  const fields = {
    assignment_ids: [31],
    active: true,
    expected_version: 4,
    reason: 'Confirmed grouping',
  };
  wrapper.findComponent(CustomersDialog).vm.$emit('save', fields);
  await flushPromises();
  expect(mocks.api.savePortfolioGroupCustomers).toHaveBeenCalledWith(
    '1400',
    18,
    fields
  );
  expect(wrapper.findComponent(CustomersDialog).exists()).toBe(false);
  expect(mocks.api.portfolioGroupCustomers).toHaveBeenCalledTimes(2);
  expect(wrapper.text()).toContain('Portfolio changes saved');
});

it('retains confirmation of a scoped transfer when the fresh read legitimately loses private group visibility', async () => {
  mocks.route.query.group_id = '18';
  mocks.api.savePortfolioGroup.mockResolvedValue({
    data: { id: 18, version: 5 },
  });
  const wrapper = render(Panel, { metadata }, true);
  await flushPromises();
  await button(wrapper, 'Edit portfolio').trigger('click');
  mocks.api.portfolioGroup.mockRejectedValue({ response: { status: 404 } });
  wrapper.findComponent(Editor).vm.$emit('save', {
    portfolio_group: { owner_id: 8 },
    expected_version: 4,
  });
  await flushPromises();
  expect(wrapper.findComponent(Editor).exists()).toBe(false);
  expect(wrapper.text()).not.toContain('Existing customer');
  expect(wrapper.text()).toContain('Portfolio changes saved');
  expect(mocks.api.savePortfolioGroup).toHaveBeenCalledTimes(1);
});

it('opens groups in the existing horizontal workspace and discards prior metadata on a role change', async () => {
  const wrapper = render(Workspace, {}, true);
  await flushPromises();
  await button(wrapper, 'Operational portfolios').trigger('click');
  await flushPromises();
  expect(mocks.route.query.section).toBe('groups');
  expect(wrapper.findComponent(Panel).exists()).toBe(true);
  mocks.api.metadata.mockRejectedValue({ response: { status: 403 } });
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  expect(wrapper.findComponent(Panel).exists()).toBe(false);
  expect(mocks.api.metadata).toHaveBeenCalledTimes(2);
});
