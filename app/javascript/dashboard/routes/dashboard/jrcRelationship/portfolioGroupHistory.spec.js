import { mount, shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import messages from 'dashboard/i18n/locale/en/relationship.json';
import History from './PortfolioGroupHistoryPanel.vue';
import Groups from './PortfolioGroupsPanel.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  portfolioGroupHistory: vi.fn(),
  exportPortfolioGroupHistory: vi.fn(),
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
const group = {
  id: 18,
  version: 4,
  can_read_history: true,
  can_export_history: true,
};
const metadata = { formatting: {} };
const data = (overrides = {}) => ({
  payload: [
    {
      id: 91,
      kind: 'updated',
      at: '2026-11-06T10:00:00Z',
      actor: { id: 7, name: 'Scoped operator' },
      changed_fields: ['objective'],
      reason_recorded: true,
    },
  ],
  meta: {
    group_id: 18,
    page: 1,
    per_page: 25,
    total: 26,
    can_read_rules: false,
    projection: 'operational_summary',
  },
  ...overrides,
});
const wrappers = [];
const render = (component = History, shallow = false) => {
  const wrapper = (shallow ? shallowMount : mount)(component, {
    props: component === History ? { group, metadata } : { metadata },
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
  mocks.portfolioGroupHistory.mockResolvedValue({ data: data() });
  mocks.portfolioGroup.mockResolvedValue({ data: group });
  mocks.portfolioGroupCustomers.mockResolvedValue({
    data: { payload: [], meta: { page: 1, per_page: 25, total: 0 } },
  });
  mocks.exportPortfolioGroupHistory.mockResolvedValue({
    data: {
      version: 1,
      projection: 'operational_summary',
      group: { id: 18 },
      events: [],
    },
  });
  vi.stubGlobal(
    'URL',
    Object.assign(class extends URL {}, {
      createObjectURL: vi.fn(() => 'blob:scoped-history'),
      revokeObjectURL: vi.fn(),
    })
  );
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
});
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

it('loads the selected account/group, paginates and applies or clears action/date filters', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('Scoped operator');
  expect(mocks.portfolioGroupHistory).toHaveBeenLastCalledWith(
    '1400',
    18,
    { page: 1 },
    { signal: expect.any(AbortSignal) }
  );
  await button(wrapper, 'Next page').trigger('click');
  await flushPromises();
  expect(mocks.portfolioGroupHistory.mock.calls.at(-1)[2]).toEqual({ page: 2 });
  await wrapper.get('select').setValue('updated');
  await wrapper.findAll('input[type="date"]')[0].setValue('2026-10-01');
  await wrapper.findAll('input[type="date"]')[1].setValue('2026-11-06');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.portfolioGroupHistory.mock.calls.at(-1)[2]).toEqual({
    page: 1,
    kind: 'updated',
    from: '2026-10-01',
    to: '2026-11-06',
  });
  await button(wrapper, 'Clear filters').trigger('click');
  await flushPromises();
  expect(mocks.portfolioGroupHistory.mock.calls.at(-1)[2]).toEqual({ page: 1 });
});

it('removes previous events on denied reload and ignores a late response after identity changes', async () => {
  let resolve;
  const wrapper = render();
  await flushPromises();
  mocks.portfolioGroupHistory.mockReturnValueOnce(
    new Promise(done => {
      resolve = done;
    })
  );
  await wrapper.get('form').trigger('submit');
  mocks.portfolioGroupHistory.mockRejectedValueOnce({
    response: { status: 403, data: { errors: ['Denied current scope'] } },
  });
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  resolve({ data: data() });
  await flushPromises();
  expect(wrapper.text()).not.toContain('Scoped operator');
  expect(wrapper.get('[role="alert"]').text()).toContain(
    'Denied current scope'
  );
});

it('never displays an HTTP 200 from a different group or projection', async () => {
  mocks.portfolioGroupHistory.mockResolvedValue({
    data: data({ meta: { group_id: 99, projection: 'operational_summary' } }),
  });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).not.toContain('Scoped operator');
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
});

it('exports only a confirmed operational summary and reports preparation without claiming a saved file', async () => {
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'Export operational summary').trigger('click');
  await flushPromises();
  expect(mocks.exportPortfolioGroupHistory).toHaveBeenCalledWith(
    '1400',
    18,
    {},
    { signal: expect.any(AbortSignal) }
  );
  expect(URL.createObjectURL).toHaveBeenCalledWith(expect.any(Blob));
  expect(HTMLAnchorElement.prototype.click).toHaveBeenCalledOnce();
  expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:scoped-history');
  expect(wrapper.text()).toContain('prepared for download');
});

it('does not download malformed success responses or late exports from a previous account', async () => {
  mocks.exportPortfolioGroupHistory.mockResolvedValueOnce({
    data: { group: { id: 99 }, projection: 'operational_summary', events: [] },
  });
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'Export operational summary').trigger('click');
  await flushPromises();
  expect(URL.createObjectURL).not.toHaveBeenCalled();
  let resolve;
  mocks.exportPortfolioGroupHistory.mockReturnValueOnce(
    new Promise(done => {
      resolve = done;
    })
  );
  await button(wrapper, 'Export operational summary').trigger('click');
  mocks.route.params.accountId = '2400';
  mocks.portfolioGroupHistory.mockRejectedValue({ response: { status: 404 } });
  await flushPromises();
  resolve({
    data: { group: { id: 18 }, projection: 'operational_summary', events: [] },
  });
  await flushPromises();
  expect(URL.createObjectURL).not.toHaveBeenCalled();
  expect(wrapper.text()).not.toContain('prepared for download');
});

it('omits unavailable actor identities, configuration choices and unauthorized export controls', async () => {
  mocks.portfolioGroupHistory.mockResolvedValue({
    data: data({ payload: [{ ...data().payload[0], actor: null }] }),
  });
  const wrapper = render();
  await wrapper.setProps({ group: { ...group, can_export_history: false } });
  await flushPromises();
  expect(wrapper.text()).not.toContain('Scoped operator');
  expect(wrapper.get('select').find('option[value="rules"]').exists()).toBe(
    false
  );
  expect(button(wrapper, 'Export operational summary')).toBeUndefined();
  expect(wrapper.get('select').find('option[value="restored"]').exists()).toBe(
    false
  );
});

it('wires the history tab and returns to customers when record-specific history access is revoked', async () => {
  const wrapper = render(Groups, true);
  await flushPromises();
  await button(wrapper, 'Portfolio history').trigger('click');
  expect(wrapper.findComponent(History).props('group')).toEqual(group);
  mocks.portfolioGroup.mockResolvedValue({
    data: { ...group, can_read_history: false, can_export_history: false },
  });
  await button(wrapper, 'Refresh').trigger('click');
  await flushPromises();
  expect(wrapper.findComponent(History).exists()).toBe(false);
  expect(button(wrapper, 'Portfolio history')).toBeUndefined();
  expect(wrapper.text()).toContain(
    'No authorized customers are linked to this portfolio.'
  );
});
