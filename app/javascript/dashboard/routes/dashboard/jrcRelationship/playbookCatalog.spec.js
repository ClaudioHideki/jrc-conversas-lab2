import { mount, shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import messages from 'dashboard/i18n/locale/en/relationship.json';
import History from './PlaybookHistoryPanel.vue';
import Panel from './ConfigurationPanel.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: { playbooks: vi.fn(), playbookHistory: vi.fn() },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));
const book = {
  id: 18,
  version: 72,
  name: 'Synthetic current native book',
  trigger_kind: 'health',
  steps: [],
  conditions: [],
};
const wrappers = [];
const render = (component = History, props = { book, allowed: true }) => {
  const wrapper = (component === Panel ? shallowMount : mount)(component, {
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
const button = (wrapper, key) =>
  wrapper
    .findAll('button')
    .find(row => row.text() === messages.RELATIONSHIP[key]);
const open = async wrapper => {
  wrapper.get('details').element.open = true;
  await wrapper.get('details').trigger('toggle');
  await flushPromises();
};
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
  mocks.api.playbookHistory.mockImplementation(async (_, id, params) => ({
    data: {
      current: structuredClone(book),
      payload: [{ version: params.page === 1 ? 72 : 1 }],
      meta: { page: params.page, per_page: 25, total: 26 },
    },
  }));
  mocks.api.playbooks.mockImplementation(async (_, options) => ({
    data: {
      payload: [{ ...book, id: options.params.page === 1 ? 18 : 118 }],
      meta: { ...options.params, total: 26 },
    },
  }));
});
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
});

it('loads saved history only when opened and pages to older versions before requesting restoration', async () => {
  const wrapper = render();
  expect(mocks.api.playbookHistory).not.toHaveBeenCalled();
  await open(wrapper);
  expect(mocks.api.playbookHistory).toHaveBeenCalledOnce();
  expect(wrapper.text()).toContain('72');
  expect(
    wrapper
      .findAll('button')
      .some(row => row.text() === messages.RELATIONSHIP.PLAYBOOK_RESTORE.OPEN)
  ).toBe(false);
  await button(wrapper, 'NEXT').trigger('click');
  await flushPromises();
  expect(mocks.api.playbookHistory).toHaveBeenLastCalledWith(
    '1400',
    18,
    { page: 2, per_page: 25 },
    expect.objectContaining({ signal: expect.any(AbortSignal) })
  );
  await wrapper
    .findAll('button')
    .find(row => row.text() === messages.RELATIONSHIP.PLAYBOOK_RESTORE.OPEN)
    .trigger('click');
  expect(wrapper.emitted('restore')).toEqual([[18, 1]]);
  await button(wrapper, 'PREVIOUS').trigger('click');
  await flushPromises();
  expect(button(wrapper, 'PREVIOUS').attributes('disabled')).toBeDefined();
});

it('rejects a stale current definition instead of rendering a misleading restoration action', async () => {
  mocks.api.playbookHistory.mockResolvedValue({
    data: { current: { ...book, version: 73 }, payload: [{ version: 1 }] },
  });
  const wrapper = render();
  await open(wrapper);
  expect(wrapper.get('[role="alert"]').text()).toBe(
    messages.RELATIONSHIP.PLAYBOOK_RESTORE.UNCONFIRMED
  );
  expect(
    wrapper
      .findAll('button')
      .some(row => row.text() === messages.RELATIONSHIP.PLAYBOOK_RESTORE.OPEN)
  ).toBe(false);
});

it('does not fetch history without native configure access', async () => {
  const wrapper = render(History, { book, allowed: false });
  expect(wrapper.find('details').exists()).toBe(false);
  expect(mocks.api.playbookHistory).not.toHaveBeenCalled();
});

it('aborts a late account response and clears historical data on membership changes', async () => {
  let resolve;
  mocks.api.playbookHistory.mockReturnValueOnce(
    new Promise(done => {
      resolve = done;
    })
  );
  const wrapper = render();
  await open(wrapper);
  const signal = mocks.api.playbookHistory.mock.calls[0][3].signal;
  mocks.route.params.accountId = '1500';
  await flushPromises();
  expect(signal.aborted).toBe(true);
  resolve({
    data: {
      current: book,
      payload: [{ version: 1 }],
      meta: { page: 1, per_page: 25, total: 1 },
    },
  });
  await flushPromises();
  expect(wrapper.text()).not.toContain(
    messages.RELATIONSHIP.PLAYBOOK_RESTORE.OPEN
  );
  expect(wrapper.emitted('restore')).toBeUndefined();
});

it('clears loaded history after the saved book version changes and makes a fresh read on reopening', async () => {
  const wrapper = render();
  await open(wrapper);
  await wrapper.setProps({ book: { ...book, version: 73 } });
  expect(wrapper.get('details').element.open).toBe(false);
  expect(wrapper.find('ul').exists()).toBe(false);
  mocks.api.playbookHistory.mockResolvedValue({
    data: {
      current: { ...book, version: 73 },
      payload: [],
      meta: { page: 1, per_page: 25, total: 0 },
    },
  });
  await open(wrapper);
  expect(wrapper.text()).toContain(messages.RELATIONSHIP.CONFIG_HISTORY_EMPTY);
});

it('removes loaded version data after a denied page and offers an explicit safe reload', async () => {
  const wrapper = render();
  await open(wrapper);
  mocks.api.playbookHistory.mockRejectedValueOnce({
    response: { status: 403, data: { error: 'Native denied' } },
  });
  await button(wrapper, 'NEXT').trigger('click');
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toContain('Native denied');
  expect(wrapper.find('li').exists()).toBe(false);
  await wrapper
    .findAll('button')
    .find(row => row.text() === messages.RELATIONSHIP.PLAYBOOK_RESTORE.RETRY)
    .trigger('click');
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
});

it('pages the catalog and resets to the first page after identity changes', async () => {
  const wrapper = render(Panel, {
    screen: 'playbooks',
    allowed: true,
    metadata: {},
  });
  await flushPromises();
  expect(mocks.api.playbooks).toHaveBeenCalledWith('1400', {
    params: { page: 1, per_page: 25 },
  });
  await button(wrapper, 'NEXT').trigger('click');
  await flushPromises();
  expect(mocks.api.playbooks).toHaveBeenLastCalledWith('1400', {
    params: { page: 2, per_page: 25 },
  });
  expect(wrapper.findComponent(History).props('book').id).toBe(118);
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  expect(mocks.api.playbooks).toHaveBeenLastCalledWith('1400', {
    params: { page: 1, per_page: 25 },
  });
});

it('prevents catalog pagination from discarding an open draft', async () => {
  const wrapper = render(Panel, {
    screen: 'playbooks',
    allowed: true,
    metadata: {},
  });
  await flushPromises();
  await button(wrapper, 'NEW').trigger('click');
  expect(button(wrapper, 'NEXT').attributes('disabled')).toBeDefined();
  await button(wrapper, 'NEXT').trigger('click');
  expect(mocks.api.playbooks).toHaveBeenCalledOnce();
});
