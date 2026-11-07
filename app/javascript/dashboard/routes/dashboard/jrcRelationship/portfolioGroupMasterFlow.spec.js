import { mount, shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import messages from 'dashboard/i18n/locale/en/relationship.json';
import Master from './PortfolioGroupMasterDialog.vue';
import Form from './PortfolioAssignmentForm.vue';
import Groups from './PortfolioGroupsPanel.vue';
import Customers from './PortfolioGroupCustomersDialog.vue';
import ModulePage from './ModulePage.vue';
import Workload from './CapacityWorkloadForm.vue';
import CompanyPicker from '../jrcCustomers/components/CompanyPicker.vue';
import MembershipBatch from './PortfolioMembershipBatchPanel.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: {
    portfolio: vi.fn(),
    saveAssignment: vi.fn(),
    metadata: vi.fn(),
    dashboard: vi.fn(),
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
const Picker = {
  name: 'CompanyPicker',
  props: ['modelValue', 'disabled'],
  emits: ['update:modelValue'],
  template: '<div />',
};
const group = {
  id: 18,
  version: 4,
  owner_id: 7,
  business_unit_id: 5,
  name: 'Existing operational portfolio',
  status: 'active',
  can_manage: true,
  goals: [],
};
const customer = {
  id: 31,
  company_id: 11,
  name: 'Existing master customer',
  owner: { id: 8, name: 'Existing native analyst' },
};
const metadata = {
  can_manage: true,
  can_team: true,
  can_configure: true,
  owners: [
    [7, 'Native coordinator'],
    [8, 'Existing native analyst'],
  ],
  teams: [[4, 'Native team']],
  units: [[5, 'Native unit']],
  segments: [[6, 'Native segment']],
  products: [[9, 'Native product']],
  pipelines: [],
};
const page = payload => ({
  data: { payload, meta: { page: 1, per_page: 25, total: payload.length } },
});
const wrappers = [];
const render = (
  component = Master,
  props = { group, metadata },
  shallow = false
) => {
  const wrapper = (shallow ? shallowMount : mount)(component, {
    props,
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
      stubs: { Dialog, CompanyPicker: Picker },
    },
  });
  wrappers.push(wrapper);
  return wrapper;
};
const button = (wrapper, text) =>
  wrapper.findAll('button').find(row => row.text() === text);
const selectCompany = async wrapper => {
  wrapper.findComponent(CompanyPicker).vm.$emit('update:modelValue', 11);
  await flushPromises();
  await button(wrapper, 'Check current Relationship allocation').trigger(
    'click'
  );
  await flushPromises();
};
beforeEach(() => {
  vi.resetAllMocks();
  mocks.route = reactive({ params: { accountId: '1400' }, query: {} });
  mocks.store = reactive({
    getters: {
      getCurrentUserID: 7,
      getCurrentRole: 'administrator',
      getCurrentUser: { accounts: [] },
    },
  });
  mocks.api.portfolio.mockResolvedValue(page([]));
  mocks.api.metadata.mockResolvedValue({ data: metadata });
  mocks.api.dashboard.mockResolvedValue({ data: {} });
  mocks.api.portfolioGroup.mockResolvedValue({ data: group });
  mocks.api.portfolioGroupCustomers.mockResolvedValue(page([]));
  mocks.api.saveAssignment.mockResolvedValue({ data: customer });
  mocks.api.savePortfolioGroupCustomers.mockResolvedValue({
    data: {
      id: 18,
      version: 5,
      results: [{ assignment_id: 31, state: 'linked' }],
    },
  });
});
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

it('reuses an existing native allocation without writes and requires explicit portfolio review', async () => {
  mocks.api.portfolio.mockResolvedValue(page([customer]));
  const wrapper = render();
  await selectCompany(wrapper);
  expect(mocks.api.portfolio).toHaveBeenCalledWith(
    '1400',
    { company_id: 11, page: 1, per_page: 1 },
    { signal: expect.any(AbortSignal) }
  );
  expect(wrapper.findComponent(Form).exists()).toBe(false);
  expect(wrapper.emitted('review')).toBeUndefined();
  expect(mocks.api.saveAssignment).not.toHaveBeenCalled();
  await button(wrapper, 'Review portfolio link').trigger('click');
  expect(wrapper.emitted('review')).toEqual([[customer]]);
  expect(mocks.api.savePortfolioGroupCustomers).not.toHaveBeenCalled();
});

it('saves the native allocation separately, retains all native inputs and does not implicitly link or transfer ownership', async () => {
  const wrapper = render();
  await selectCompany(wrapper);
  const form = wrapper.findComponent(Form);
  expect(form.props('lockCompany')).toBe(true);
  expect(form.props('initialValue')).toMatchObject({
    company_id: 11,
    owner_id: 7,
    business_unit_id: 5,
  });
  await form.findAll('select')[0].setValue(8);
  await form.findAll('select')[1].setValue(4);
  await form.findAll('select')[3].setValue(6);
  await form.findAll('select')[4].setValue(9);
  await form.get('input:not([type])').setValue('Explicit native complexity');
  await form
    .get('[data-testid="eligibility-exception-reason"]')
    .setValue('Recorded native exception reason');
  form.findComponent(Workload).vm.$emit('update:modelValue', { hours: 2.5 });
  await form.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.api.saveAssignment).toHaveBeenCalledWith(
    '1400',
    expect.objectContaining({
      company_id: 11,
      owner_id: 8,
      team_id: 4,
      business_unit_id: 5,
      exception_reason: 'Recorded native exception reason',
      settings: {
        segment_id: 6,
        product_id: 9,
        complexity: 'Explicit native complexity',
        capacity_workload: { hours: 2.5 },
      },
    })
  );
  expect(wrapper.text()).toContain('Native allocation saved');
  expect(wrapper.emitted('review')).toBeUndefined();
  expect(mocks.api.savePortfolioGroupCustomers).not.toHaveBeenCalled();
});

it('retains the allocation draft on native rejection and blocks duplicate retry after an unconfirmed success until a current lookup', async () => {
  const wrapper = render();
  await selectCompany(wrapper);
  mocks.api.saveAssignment.mockRejectedValueOnce({
    response: { status: 422, data: { errors: ['Native capacity limit'] } },
  });
  const form = wrapper.findComponent(Form);
  await form
    .get('[data-testid="eligibility-exception-reason"]')
    .setValue('Retained native reason');
  await form.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toContain(
    'Native capacity limit'
  );
  expect(
    form.get('[data-testid="eligibility-exception-reason"]').element.value
  ).toBe('Retained native reason');
  mocks.api.saveAssignment.mockResolvedValueOnce({
    data: { id: 31, company_id: 99 },
  });
  await form.get('form').trigger('submit');
  await flushPromises();
  await form.get('form').trigger('submit');
  expect(mocks.api.saveAssignment).toHaveBeenCalledTimes(2);
  expect(wrapper.emitted('review')).toBeUndefined();
  mocks.api.portfolio.mockResolvedValue(page([customer]));
  await button(wrapper, 'Check current Relationship allocation').trigger(
    'click'
  );
  await flushPromises();
  expect(wrapper.text()).toContain('Existing native allocation selected');
});

it('drops a late allocation response and closes the workflow after current role authority changes', async () => {
  const wrapper = render();
  await selectCompany(wrapper);
  let resolve;
  mocks.api.saveAssignment.mockReturnValueOnce(
    new Promise(done => {
      resolve = done;
    })
  );
  await wrapper.findComponent(Form).get('form').trigger('submit');
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  resolve({ data: customer });
  await flushPromises();
  expect(wrapper.emitted('close')).toHaveLength(1);
  expect(wrapper.emitted('review')).toBeUndefined();
  expect(wrapper.text()).not.toContain('Native allocation saved');
});

it('requires a current read after an interrupted mutation instead of retrying an allocation with an unknown commit result', async () => {
  const wrapper = render();
  await selectCompany(wrapper);
  mocks.api.saveAssignment.mockRejectedValueOnce(
    new Error('Connection interrupted')
  );
  const form = wrapper.findComponent(Form);
  await form.get('form').trigger('submit');
  await flushPromises();
  await form.get('form').trigger('submit');
  expect(mocks.api.saveAssignment).toHaveBeenCalledOnce();
  expect(wrapper.emitted('review')).toBeUndefined();
  mocks.api.portfolio.mockResolvedValue(page([customer]));
  await button(wrapper, 'Check current Relationship allocation').trigger(
    'click'
  );
  await flushPromises();
  expect(wrapper.text()).toContain('Existing native allocation selected');
  expect(wrapper.findComponent(Form).exists()).toBe(false);
});

it('does not close the workflow at initial mount and does not submit a disabled native form', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.emitted('close')).toBeUndefined();
  const form = render(Form, {
    metadata,
    initialValue: { company_id: 11 },
    disabled: true,
  });
  await form.get('form').trigger('submit');
  expect(form.emitted('submit')).toBeUndefined();
});

it('denies native lookup or allocation when the portfolio is archived or native team authority is unavailable', async () => {
  const wrapper = render(Master, {
    group: { ...group, status: 'archived' },
    metadata,
  });
  wrapper.findComponent(CompanyPicker).vm.$emit('update:modelValue', 11);
  await flushPromises();
  await button(wrapper, 'Check current Relationship allocation').trigger(
    'click'
  );
  expect(mocks.api.portfolio).not.toHaveBeenCalled();
  expect(mocks.api.saveAssignment).not.toHaveBeenCalled();
});

it('preserves the explicit allocation form in the original native page and routes its submitted fields to the same API', async () => {
  const wrapper = render(ModulePage, { screen: 'portfolio' }, true);
  await flushPromises();
  await button(wrapper, messages.RELATIONSHIP.ADD_CUSTOMER).trigger('click');
  const form = wrapper.findComponent(Form);
  const fields = {
    company_id: 11,
    owner_id: 7,
    team_id: '',
    business_unit_id: '',
    exception_reason: 'Native reason',
    settings: { complexity: 'Explicit' },
  };
  form.vm.$emit('submit', fields);
  await flushPromises();
  expect(mocks.api.saveAssignment).toHaveBeenCalledWith('1400', {
    ...fields,
    team_id: null,
    business_unit_id: null,
  });
  expect(wrapper.findComponent(Form).exists()).toBe(false);
});

it('passes the selected master allocation into the existing reason/revision review and persists only after explicit confirmation', async () => {
  mocks.route.query = { group_id: '18' };
  const wrapper = render(Groups, { metadata }, true);
  await flushPromises();
  await button(wrapper, 'Select from master directory').trigger('click');
  wrapper.findComponent(Master).vm.$emit('review', customer);
  await flushPromises();
  const review = wrapper.findComponent(Customers);
  expect(review.props('initialCustomer')).toEqual(customer);
  expect(review.props('customer')).toBeNull();
  expect(mocks.api.savePortfolioGroupCustomers).not.toHaveBeenCalled();
  review.vm.$emit('save', {
    assignment_ids: [31],
    active: true,
    expected_version: 4,
    reason: 'Explicit reviewed master link',
  });
  await flushPromises();
  expect(mocks.api.savePortfolioGroupCustomers).toHaveBeenCalledWith(
    '1400',
    18,
    {
      assignment_ids: [31],
      active: true,
      expected_version: 4,
      reason: 'Explicit reviewed master link',
    }
  );
});

it('starts the native link dialog on review for the chosen master customer and keeps creation separate from link deactivation', async () => {
  const wrapper = render(Customers, { group, initialCustomer: customer });
  await flushPromises();
  expect(mocks.api.portfolio).not.toHaveBeenCalled();
  expect(wrapper.text()).toContain(customer.name);
  await wrapper.get('textarea').setValue('Reviewed existing master customer');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')).toEqual([
    [
      {
        assignment_ids: [31],
        active: true,
        expected_version: 4,
        reason: 'Reviewed existing master customer',
      },
    ],
  ]);
});

it('collects several existing master allocations and requires one explicit reason before preparing their native link review', async () => {
  mocks.api.portfolio
    .mockResolvedValueOnce(page([customer]))
    .mockResolvedValueOnce(
      page([
        { ...customer, id: 32, company_id: 12, name: 'Second native customer' },
      ])
    );
  const wrapper = render();
  await selectCompany(wrapper);
  await wrapper.get('[data-test="master-add-selection"]').trigger('click');
  await flushPromises();
  wrapper.findComponent(CompanyPicker).vm.$emit('update:modelValue', 12);
  await flushPromises();
  await button(wrapper, 'Check current Relationship allocation').trigger(
    'click'
  );
  await flushPromises();
  await wrapper.get('[data-test="master-add-selection"]').trigger('click');
  await flushPromises();
  expect(wrapper.findAll('[data-test="master-selection-row"]')).toHaveLength(2);
  expect(
    wrapper.get('[data-test="master-review-selection"]').element.disabled
  ).toBe(true);
  await wrapper.get('[data-test="master-selection-review"]').trigger('submit');
  expect(wrapper.emitted('batch')).toBeUndefined();
  await wrapper
    .get('[data-test="master-selection-reason"]')
    .setValue(' Reviewed native customer collection ');
  await wrapper.get('[data-test="master-selection-review"]').trigger('submit');
  await wrapper.get('[data-test="master-selection-review"]').trigger('submit');
  expect(wrapper.emitted('batch')).toEqual([
    [
      {
        assignment_ids: [31, 32],
        active: true,
        expected_version: 4,
        reason: 'Reviewed native customer collection',
      },
    ],
  ]);
  expect(mocks.api.saveAssignment).not.toHaveBeenCalled();
  expect(mocks.api.savePortfolioGroupCustomers).not.toHaveBeenCalled();
});

it('deduplicates selected native customers and lets the user clear the current choice without losing the collected draft', async () => {
  mocks.api.portfolio.mockResolvedValue(page([customer]));
  const wrapper = render();
  await selectCompany(wrapper);
  await wrapper.get('[data-test="master-add-selection"]').trigger('click');
  await flushPromises();
  await wrapper
    .get('[data-test="master-selection-reason"]')
    .setValue('Preserved collection reason');
  await selectCompany(wrapper);
  expect(
    wrapper.get('[data-test="master-add-selection"]').element.disabled
  ).toBe(true);
  expect(
    wrapper.get('[data-test="master-review-selection"]').element.disabled
  ).toBe(true);
  await wrapper.get('[data-test="master-another-customer"]').trigger('click');
  await flushPromises();
  expect(wrapper.findAll('[data-test="master-selection-row"]')).toHaveLength(1);
  expect(
    wrapper.get('[data-test="master-selection-reason"]').element.value
  ).toBe('Preserved collection reason');
  await wrapper.get('[data-test="master-remove-selection"]').trigger('click');
  await flushPromises();
  expect(wrapper.findAll('[data-test="master-selection-row"]')).toHaveLength(0);
  expect(mocks.api.saveAssignment).not.toHaveBeenCalled();
  expect(mocks.api.savePortfolioGroupCustomers).not.toHaveBeenCalled();
});

it('bounds selection at fifty with ten visible rows and reopens capacity when removing a staged customer', async () => {
  mocks.api.portfolio.mockImplementation(async (_, params) =>
    page([
      {
        id: 1000 + params.company_id,
        company_id: params.company_id,
        name: `Synthetic selected ${params.company_id}`,
      },
    ])
  );
  const wrapper = render();
  /* eslint-disable no-await-in-loop -- Each interaction uses the same picker and must finish before selecting the next company. */
  for (let id = 1; id <= 50; id += 1) {
    wrapper.findComponent(CompanyPicker).vm.$emit('update:modelValue', id);
    await flushPromises();
    await button(wrapper, 'Check current Relationship allocation').trigger(
      'click'
    );
    await flushPromises();
    await wrapper.get('[data-test="master-add-selection"]').trigger('click');
    await flushPromises();
  }
  /* eslint-enable no-await-in-loop */
  expect(wrapper.findAll('[data-test="master-selection-row"]')).toHaveLength(
    10
  );
  expect(wrapper.findComponent(CompanyPicker).props('disabled')).toBe(true);
  expect(
    wrapper.get('[data-test="master-selection-next"]').element.disabled
  ).toBe(true);
  await wrapper.get('[data-test="master-selection-previous"]').trigger('click');
  await flushPromises();
  expect(
    wrapper.get('[data-test="master-selection-next"]').element.disabled
  ).toBe(false);
  await wrapper
    .findAll('[data-test="master-remove-selection"]')[0]
    .trigger('click');
  await flushPromises();
  expect(wrapper.findComponent(CompanyPicker).props('disabled')).toBe(false);
  expect(mocks.api.saveAssignment).not.toHaveBeenCalled();
});

it('keeps missing allocation creation explicit and preserves its native receipt separately from the collected link review', async () => {
  const wrapper = render();
  await selectCompany(wrapper);
  expect(wrapper.find('[data-test="master-add-selection"]').exists()).toBe(
    false
  );
  wrapper
    .findComponent(Form)
    .vm.$emit('submit', { company_id: 11, owner_id: 7 });
  await flushPromises();
  expect(mocks.api.saveAssignment).toHaveBeenCalledOnce();
  await wrapper.get('[data-test="master-add-selection"]').trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain(customer.name);
  expect(wrapper.text()).toContain(
    messages.RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.SELECTION_NOTICE
  );
  expect(wrapper.emitted('batch')).toBeUndefined();
  expect(mocks.api.savePortfolioGroupCustomers).not.toHaveBeenCalled();
});

it('clears collected private names and reason when native authority changes', async () => {
  mocks.api.portfolio.mockResolvedValue(page([customer]));
  const wrapper = render();
  await selectCompany(wrapper);
  await wrapper.get('[data-test="master-add-selection"]').trigger('click');
  await flushPromises();
  await wrapper
    .get('[data-test="master-selection-reason"]')
    .setValue('Private native reason');
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  expect(wrapper.text()).not.toContain(customer.name);
  expect(wrapper.find('[data-test="master-selection-reason"]').exists()).toBe(
    false
  );
  expect(wrapper.emitted('close')).toHaveLength(1);
  expect(wrapper.emitted('batch')).toBeUndefined();
});

it('passes a collected master audience to the existing durable membership panel using the captured view context', async () => {
  mocks.route.query = { group_id: '18' };
  const wrapper = render(Groups, { metadata }, true);
  await flushPromises();
  await button(wrapper, 'Select from master directory').trigger('click');
  wrapper.findComponent(Master).vm.$emit('batch', {
    assignment_ids: [31, 32],
    active: true,
    expected_version: 4,
    reason: 'Reviewed selection',
  });
  await flushPromises();
  expect(wrapper.findComponent(Master).exists()).toBe(false);
  expect(wrapper.findComponent(MembershipBatch).props('proposal')).toEqual({
    operation: 'portfolio_membership',
    ids: [31, 32],
    portfolio_group_id: 18,
    expected_version: 4,
    active: true,
    justification: 'Reviewed selection',
    request_id: expect.any(String),
  });
  expect(mocks.api.savePortfolioGroupCustomers).not.toHaveBeenCalled();
});

it('stages two missing native allocations without saving either before the full company-subject review', async () => {
  const wrapper = render(Master, { group, metadata, staged: true });
  await selectCompany(wrapper);
  wrapper.findComponent(Form).vm.$emit('submit', {
    company_id: 11,
    owner_id: 7,
    team_id: '',
    business_unit_id: 5,
    exception_reason: '  Explicit eligible exception  ',
    settings: { capacity_workload: { hours: 1.5 } },
  });
  await flushPromises();
  await wrapper.get('[data-test="master-add-selection"]').trigger('click');
  await flushPromises();
  wrapper.findComponent(CompanyPicker).vm.$emit('update:modelValue', 12);
  await flushPromises();
  await button(wrapper, 'Check current Relationship allocation').trigger(
    'click'
  );
  await flushPromises();
  wrapper
    .findComponent(Form)
    .vm.$emit('submit', { company_id: 12, owner_id: 8, exception_reason: '' });
  await flushPromises();
  await wrapper.get('[data-test="master-add-selection"]').trigger('click');
  await flushPromises();
  await wrapper
    .get('[data-test="master-selection-reason"]')
    .setValue('Review both prepared allocations');
  await wrapper.get('[data-test="master-selection-review"]').trigger('submit');
  const result = wrapper.emitted('masterBatch')[0][0];
  expect(result.company_ids).toEqual([11, 12]);
  expect(result.creations).toEqual([
    {
      company_id: 11,
      owner_id: 7,
      team_id: null,
      business_unit_id: 5,
      exception_reason: 'Explicit eligible exception',
      settings: { capacity_workload: { hours: 1.5 } },
    },
    { company_id: 12, owner_id: 8, team_id: null, business_unit_id: null },
  ]);
  expect(wrapper.emitted('batch')).toBeUndefined();
  expect(wrapper.emitted('review')).toBeUndefined();
  expect(mocks.api.saveAssignment).not.toHaveBeenCalled();
  expect(mocks.api.savePortfolioGroupCustomers).not.toHaveBeenCalled();
});

it('deduplicates staged companies without treating their absent allocation IDs as the same customer', async () => {
  const wrapper = render(Master, { group, metadata, staged: true });
  await selectCompany(wrapper);
  wrapper
    .findComponent(Form)
    .vm.$emit('submit', { company_id: 11, owner_id: 7 });
  await flushPromises();
  await wrapper.get('[data-test="master-add-selection"]').trigger('click');
  await flushPromises();
  await selectCompany(wrapper);
  wrapper
    .findComponent(Form)
    .vm.$emit('submit', { company_id: 11, owner_id: 8 });
  await flushPromises();
  expect(
    wrapper.get('[data-test="master-add-selection"]').element.disabled
  ).toBe(true);
  await wrapper.get('[data-test="master-another-customer"]').trigger('click');
  await flushPromises();
  await wrapper.get('[data-test="master-remove-selection"]').trigger('click');
  expect(wrapper.findAll('[data-test="master-selection-row"]')).toHaveLength(0);
  expect(mocks.api.saveAssignment).not.toHaveBeenCalled();
});

it('opens a distinct staged master mode and hands company IDs and native proposals to the same durable group panel', async () => {
  mocks.route.query = { group_id: '18' };
  const wrapper = render(Groups, { metadata }, true);
  await flushPromises();
  await wrapper.get('[data-test="master-reviewed-create"]').trigger('click');
  expect(wrapper.findComponent(Master).props('staged')).toBe(true);
  const creations = [{ company_id: 11, owner_id: 7 }];
  wrapper.findComponent(Master).vm.$emit('masterBatch', {
    company_ids: [11, 12],
    creations,
    expected_version: 4,
    reason: 'Reviewed company subjects',
  });
  await flushPromises();
  expect(wrapper.findComponent(MembershipBatch).props('proposal')).toEqual({
    operation: 'master_allocation',
    ids: [11, 12],
    creations,
    portfolio_group_id: 18,
    expected_version: 4,
    justification: 'Reviewed company subjects',
    request_id: expect.any(String),
  });
  expect(mocks.api.saveAssignment).not.toHaveBeenCalled();
});

it('clears staged allocation proposals on native authority changes without issuing creation or membership commands', async () => {
  const wrapper = render(Master, { group, metadata, staged: true });
  await selectCompany(wrapper);
  wrapper
    .findComponent(Form)
    .vm.$emit('submit', { company_id: 11, owner_id: 7 });
  await flushPromises();
  await wrapper.get('[data-test="master-add-selection"]').trigger('click');
  await flushPromises();
  mocks.store.getters.getCurrentUserID = 99;
  await flushPromises();
  expect(wrapper.findAll('[data-test="master-selection-row"]')).toHaveLength(0);
  expect(wrapper.emitted('close')).toHaveLength(1);
  expect(mocks.api.saveAssignment).not.toHaveBeenCalled();
});
