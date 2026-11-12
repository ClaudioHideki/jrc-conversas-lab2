import { mount, shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import messages from 'dashboard/i18n/locale/en/relationship.json';
import Customers from './PortfolioGroupCustomersDialog.vue';
import Groups from './PortfolioGroupsPanel.vue';
import { confirmedMembership } from './portfolioGroupMembershipReceipt';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: {
    portfolioGroupCustomerReview: vi.fn(),
    portfolioGroup: vi.fn(),
    portfolioGroupCustomers: vi.fn(),
    savePortfolioGroupCustomers: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: vi.fn() }),
}));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
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
const group = {
  id: 18,
  version: 4,
  name: 'Current portfolio',
  can_manage: true,
  status: 'active',
  goals: [],
};
const customer = { id: 31, name: 'Earlier customer name' };
const metadata = { can_manage: true, can_team: true };
const fields = {
  assignment_ids: [31],
  active: true,
  expected_version: 4,
  reason: 'Preserved reviewed reason',
};
const wrappers = [];
const render = (
  component = Customers,
  props = { group, initialCustomer: customer },
  shallow = false
) => {
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
beforeEach(() => {
  vi.resetAllMocks();
  mocks.route = reactive({
    params: { accountId: '1400' },
    query: { group_id: '18' },
  });
  mocks.store = reactive({
    getters: {
      getCurrentUserID: 7,
      getCurrentRole: 'administrator',
      getCurrentUser: { accounts: [] },
    },
  });
  mocks.api.portfolioGroup.mockResolvedValue({ data: group });
  mocks.api.portfolioGroupCustomers.mockResolvedValue({
    data: { payload: [], meta: { page: 1, per_page: 25, total: 0 } },
  });
  mocks.api.portfolioGroupCustomerReview.mockResolvedValue({
    data: {
      group: { id: 18, version: 5 },
      payload: [{ id: 31, name: 'Current permitted name', linked: false }],
    },
  });
  mocks.api.savePortfolioGroupCustomers.mockResolvedValue({
    data: {
      id: 18,
      version: 5,
      results: [{ assignment_id: 31, state: 'linked' }],
    },
  });
});
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

it('confirms exact committed IDs, operation states and changed/no-op revisions instead of trusting a bare HTTP200', () => {
  expect(
    confirmedMembership(
      { version: 5, results: [{ assignment_id: 31, state: 'linked' }] },
      fields
    )
  ).toBe(true);
  expect(
    confirmedMembership(
      { version: 4, results: [{ assignment_id: 31, state: 'already_linked' }] },
      fields
    )
  ).toBe(true);
  expect(confirmedMembership({ version: 5 }, fields)).toBe(false);
  expect(
    confirmedMembership(
      { version: 5, results: [{ assignment_id: 99, state: 'linked' }] },
      fields
    )
  ).toBe(false);
  expect(
    confirmedMembership(
      { version: 5, results: [{ assignment_id: 31, state: 'unlinked' }] },
      fields
    )
  ).toBe(false);
  expect(
    confirmedMembership(
      { version: 5, results: [{ assignment_id: 31, state: 'already_linked' }] },
      fields
    )
  ).toBe(false);
  expect(confirmedMembership({ version: 5, results: [null] }, fields)).toBe(
    false
  );
});

it('preserves the draft reason and selected IDs, loads a new revision and requires another explicit confirmation', async () => {
  const wrapper = render();
  await wrapper.get('textarea').setValue(fields.reason);
  await wrapper.get('form').trigger('submit');
  await wrapper.setProps({ conflict: true, error: 'Old revision' });
  await button(wrapper, 'Reload selected customers for a new review').trigger(
    'click'
  );
  await flushPromises();
  expect(mocks.api.portfolioGroupCustomerReview).toHaveBeenCalledWith(
    '1400',
    18,
    { assignment_ids: [31] },
    { signal: expect.any(AbortSignal) }
  );
  expect(wrapper.get('textarea').element.value).toBe(fields.reason);
  expect(wrapper.text()).toContain('Current permitted name');
  expect(wrapper.text()).not.toContain('Earlier customer name');
  expect(wrapper.emitted('reviewed')).toHaveLength(1);
  expect(wrapper.emitted('save')).toHaveLength(1);
  await wrapper.setProps({ conflict: false, error: '' });
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[1][0]).toEqual({
    ...fields,
    expected_version: 5,
  });
});

it('clears selected names after scope denial and does not hide the fresh error behind the old revision error', async () => {
  mocks.api.portfolioGroupCustomerReview.mockRejectedValue({
    response: { status: 403, data: { errors: ['Current access denied'] } },
  });
  const wrapper = render();
  await wrapper.setProps({ conflict: true, error: 'Old revision' });
  await button(wrapper, 'Reload selected customers for a new review').trigger(
    'click'
  );
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toBe('Current access denied');
  expect(wrapper.text()).not.toContain('Earlier customer name');
  expect(wrapper.emitted('reviewed')).toBeUndefined();
  expect(wrapper.get('button[type="submit"]').element.disabled).toBe(true);
});

it('does not silently rebase against a wrong group or a substituted selection', async () => {
  mocks.api.portfolioGroupCustomerReview.mockResolvedValueOnce({
    data: {
      group: { id: 99, version: 5 },
      payload: [{ id: 31, name: 'Wrong group', linked: false }],
    },
  });
  const wrapper = render();
  await wrapper.setProps({ conflict: true });
  await button(wrapper, 'Reload selected customers for a new review').trigger(
    'click'
  );
  await flushPromises();
  expect(wrapper.emitted('reviewed')).toBeUndefined();
  expect(wrapper.text()).not.toContain('Wrong group');
  mocks.api.portfolioGroupCustomerReview.mockResolvedValueOnce({
    data: {
      group: { id: 18, version: 5 },
      payload: [{ id: 99, name: 'Substituted customer', linked: true }],
    },
  });
  await button(wrapper, 'Reload selected customers for a new review').trigger(
    'click'
  );
  await flushPromises();
  expect(wrapper.emitted('reviewed')).toBeUndefined();
  expect(wrapper.text()).not.toContain('Substituted customer');
});

it('discards late re-review after a role change and preserves native removal semantics', async () => {
  let resolve;
  mocks.api.portfolioGroupCustomerReview.mockReturnValue(
    new Promise(done => {
      resolve = done;
    })
  );
  const wrapper = render(Customers, { group, customer, conflict: true });
  await wrapper.get('textarea').setValue(fields.reason);
  await button(wrapper, 'Reload selected customers for a new review').trigger(
    'click'
  );
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  resolve({
    data: {
      group: { id: 18, version: 5 },
      payload: [{ id: 31, name: 'Late private name', linked: true }],
    },
  });
  await flushPromises();
  expect(wrapper.emitted('close')).toHaveLength(1);
  expect(wrapper.emitted('reviewed')).toBeUndefined();
  expect(wrapper.text()).not.toContain('Late private name');
  expect(
    confirmedMembership(
      { version: 5, results: [{ assignment_id: 31, state: 'unlinked' }] },
      { ...fields, active: false }
    )
  ).toBe(true);
});

it('renders committed per-item states and retains the review when the membership receipt is missing', async () => {
  const wrapper = render(Groups, { metadata }, true);
  await flushPromises();
  await button(wrapper, 'Add existing customers').trigger('click');
  mocks.api.savePortfolioGroupCustomers.mockResolvedValueOnce({
    data: { id: 18, version: 5 },
  });
  wrapper.findComponent(Customers).vm.$emit('save', fields);
  await flushPromises();
  expect(wrapper.findComponent(Customers).exists()).toBe(true);
  expect(wrapper.text()).not.toContain('Customer link results');
  wrapper.findComponent(Customers).vm.$emit('save', fields);
  await flushPromises();
  expect(wrapper.findComponent(Customers).exists()).toBe(false);
  expect(wrapper.text()).toContain('Customer allocation #31');
  expect(wrapper.text()).toContain('Link activated');
});
