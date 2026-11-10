import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import messages from 'dashboard/i18n/locale/en/relationship.json';
import History from './PortfolioGroupHistoryPanel.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  portfolioGroupHistory: vi.fn(),
  exportPortfolioGroupHistory: vi.fn(),
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => mocks.store }));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks }));

const labels = messages.RELATIONSHIP.NAMED_PORTFOLIOS;
const response = () => ({
  payload: [
    {
      id: 91,
      kind: 'updated',
      at: '2026-11-06T10:00:00Z',
      actor: { id: 7, name: 'Previously authorized operator' },
      changed_fields: ['objective'],
      reason_recorded: true,
    },
  ],
  meta: {
    group_id: 18,
    page: 1,
    per_page: 25,
    total: 26,
    can_read_rules: true,
    projection: 'operational_summary',
  },
});
let wrapper;
const button = text =>
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
  mocks.portfolioGroupHistory.mockResolvedValue({ data: response() });
  vi.stubGlobal(
    'URL',
    Object.assign(class extends URL {}, {
      createObjectURL: vi.fn(),
      revokeObjectURL: vi.fn(),
    })
  );
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
  wrapper = mount(History, {
    props: {
      group: { id: 18, can_read_history: true, can_export_history: true },
      metadata: { formatting: {} },
    },
  });
});
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

it.each([401, 403, 404])(
  'conceals previously loaded history after an explicit native export denial %i',
  async status => {
    await flushPromises();
    expect(wrapper.text()).toContain('Previously authorized operator');
    expect(button(labels.NEXT_PAGE).element.disabled).toBe(false);
    mocks.exportPortfolioGroupHistory.mockRejectedValueOnce({
      response: { status, data: { errors: ['Native access denied'] } },
    });
    await button(labels.HISTORY.EXPORT).trigger('click');
    await flushPromises();
    expect(wrapper.text()).not.toContain('Previously authorized operator');
    expect(wrapper.findAll('ol li')).toHaveLength(0);
    expect(wrapper.get('select').find('option[value="rules"]').exists()).toBe(
      false
    );
    expect(button(labels.NEXT_PAGE).element.disabled).toBe(true);
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'Native access denied'
    );
    expect(URL.createObjectURL).not.toHaveBeenCalled();
  }
);

it('retains the already authorized read result on a transient export failure', async () => {
  await flushPromises();
  mocks.exportPortfolioGroupHistory.mockRejectedValueOnce({
    response: { status: 500, data: { errors: ['Temporary export failure'] } },
  });
  await button(labels.HISTORY.EXPORT).trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain('Previously authorized operator');
  expect(wrapper.get('[role="alert"]').text()).toContain(
    'Temporary export failure'
  );
  expect(URL.createObjectURL).not.toHaveBeenCalled();
});

it('can read again only through a fresh native response after export access was denied', async () => {
  await flushPromises();
  mocks.exportPortfolioGroupHistory.mockRejectedValueOnce({
    response: { status: 403, data: { errors: ['Export denied'] } },
  });
  await button(labels.HISTORY.EXPORT).trigger('click');
  await flushPromises();
  expect(wrapper.findAll('ol li')).toHaveLength(0);
  const current = response();
  current.payload[0].actor.name = 'Currently authorized operator';
  mocks.portfolioGroupHistory.mockResolvedValueOnce({ data: current });
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.portfolioGroupHistory).toHaveBeenCalledTimes(2);
  expect(wrapper.text()).toContain('Currently authorized operator');
  expect(wrapper.text()).not.toContain('Previously authorized operator');
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
});

it('does not download a pending export after its history view was unmounted', async () => {
  await flushPromises();
  let resolve;
  mocks.exportPortfolioGroupHistory.mockReturnValueOnce(
    new Promise(done => {
      resolve = done;
    })
  );
  await button(labels.HISTORY.EXPORT).trigger('click');
  wrapper.unmount();
  resolve({
    data: { group: { id: 18 }, projection: 'operational_summary', events: [] },
  });
  await flushPromises();
  expect(URL.createObjectURL).not.toHaveBeenCalled();
  expect(HTMLAnchorElement.prototype.click).not.toHaveBeenCalled();
});
