import { shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createStore } from 'vuex';
import { beforeEach, afterEach, expect, it, vi } from 'vitest';
import ProposalsIndex from '../ProposalsIndex.vue';
import proposalModule from 'dashboard/store/crm/modules/proposals';
const mocks = vi.hoisted(() => ({
  route: null,
  router: { push: vi.fn() },
  alert: vi.fn(),
  proposals: {
    show: vi.fn(),
    list: vi.fn(),
    pdf: vi.fn(),
    update: vi.fn(),
    convertToOrder: vi.fn(),
    create: vi.fn(),
    requestApproval: vi.fn(),
  },
  products: { list: vi.fn() },
  deals: { list: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => mocks.router,
}));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));
vi.mock('dashboard/api/crm', () => ({
  proposalsAPI: mocks.proposals,
  productsAPI: mocks.products,
  dealsAPI: mocks.deals,
}));
const record = (id = 1, title = 'Synthetic private proposal') => ({
  id,
  title,
  status: 'draft',
  version_number: 1,
  items: [],
  commercial_notes: 'Synthetic private notes',
  locked: false,
});
let wrapper;
let authority;
let store;
let download;
const mountPage = async (query = { proposalId: '1' }) => {
  mocks.route = reactive({ params: { accountId: '1' }, query });
  authority = reactive({
    id: 25,
    role: 'administrator',
    accounts: [{ id: 1, role: 'administrator' }],
  });
  store = createStore({
    getters: {
      getCurrentUserID: () => authority.id,
      getCurrentUser: () => authority,
      getCurrentRole: () => authority.role,
      getCurrentAccountId: () => Number(mocks.route.params.accountId),
      'jrcCrm/proposals/allProposals': () => [
        record(1),
        record(2, 'Synthetic second proposal'),
      ],
      'accounts/isFeatureEnabledonAccount': () => () => true,
    },
  });
  store.dispatch = vi.fn().mockResolvedValue();
  wrapper = shallowMount(ProposalsIndex, { global: { plugins: [store] } });
  await flushPromises();
  return wrapper;
};
const button = text =>
  wrapper.findAll('button').find(row => row.text().includes(text));
beforeEach(() => {
  vi.resetAllMocks();
  vi.useFakeTimers();
  sessionStorage.clear();
  mocks.proposals.show.mockResolvedValue({ data: record() });
  mocks.proposals.list.mockResolvedValue({ data: [] });
  mocks.products.list.mockResolvedValue({ data: [] });
  mocks.deals.list.mockResolvedValue({ data: [] });
  const NativeURL = URL;
  download = vi.fn(() => 'blob:synthetic-proposal-download');
  class DownloadURL extends NativeURL {
    static createObjectURL = download;

    static revokeObjectURL = vi.fn();
  }
  vi.stubGlobal('URL', DownloadURL);
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
});
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
  vi.runAllTimers();
  vi.useRealTimers();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

it('clears a loaded commercial proposal and edited notes immediately when the native role changes', async () => {
  await mountPage();
  await wrapper
    .findAll('aside textarea')[1]
    .setValue('Private former-role draft');
  authority.role = 'agent';
  authority.accounts = [{ id: 1, role: 'agent' }];
  await flushPromises();
  expect(wrapper.find('aside').exists()).toBe(false);
  expect(
    wrapper
      .findAll('textarea')
      .some(row => row.element.value.includes('Private former-role draft'))
  ).toBe(false);
});

it('rejects a late proposal detail after its account was replaced', async () => {
  let finish;
  mocks.proposals.show.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await mountPage();
  mocks.route.params.accountId = '2';
  mocks.proposals.show.mockRejectedValue({ response: { status: 404 } });
  await flushPromises();
  finish({ data: record(1, 'Synthetic previous-account private result') });
  await flushPromises();
  expect(wrapper.find('aside').exists()).toBe(false);
  expect(wrapper.text()).not.toContain(
    'Synthetic previous-account private result'
  );
});

it('does not download a late authenticated PDF after a different actor has become current', async () => {
  let finish;
  mocks.proposals.pdf.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await mountPage();
  await button('Baixar PDF').trigger('click');
  authority.id = 99;
  await flushPromises();
  finish({ data: new Blob(['%PDF synthetic private']) });
  await flushPromises();
  expect(download).not.toHaveBeenCalled();
});

it('does not navigate using a late order-conversion result after native authority changed', async () => {
  let finish;
  mocks.proposals.show.mockResolvedValue({
    data: { ...record(), status: 'accepted', locked: true },
  });
  mocks.proposals.convertToOrder.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await mountPage();
  await button('Converter em pedido').trigger('click');
  authority.accounts = [{ id: 1, role: 'agent', custom_role_id: 20 }];
  await flushPromises();
  finish({ data: { id: 9, order_number: 'SYNTHETIC-OLD-AUTHORITY' } });
  await flushPromises();
  expect(mocks.router.push).not.toHaveBeenCalled();
});

it('does not replace the currently selected proposal with the result of an older detail request', async () => {
  let finish;
  mocks.proposals.show.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await mountPage();
  mocks.proposals.show.mockResolvedValue({
    data: record(2, 'Synthetic current proposal'),
  });
  await wrapper.findAll('button[title="Editar"]')[1].trigger('click');
  await flushPromises();
  finish({ data: record(1, 'Synthetic outdated detail') });
  await flushPromises();
  expect(wrapper.get('aside').text()).toContain('Synthetic current proposal');
  expect(wrapper.get('aside').text()).not.toContain(
    'Synthetic outdated detail'
  );
});

it('does not commit a pending list to the shared native store after account or role changes', async () => {
  let finish;
  const current = reactive({ account: 1, id: 25, role: 'administrator' });
  const native = createStore({
    getters: {
      getCurrentAccountId: () => current.account,
      getCurrentUserID: () => current.id,
      getCurrentRole: () => current.role,
      getCurrentUser: () => ({
        accounts: [{ id: current.account, role: current.role }],
      }),
    },
    modules: {
      proposals: {
        ...proposalModule,
        state: structuredClone(proposalModule.state),
      },
    },
  });
  mocks.proposals.list.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const request = native.dispatch('proposals/fetchProposals');
  current.account = 2;
  current.role = 'agent';
  finish({ data: [record(1, 'Synthetic former authority list')] });
  await request;
  expect(native.getters['proposals/allProposals']).toEqual([]);
  expect(native.state.proposals.proposals).toEqual([]);
});

it('does not follow a committed save by an approval request after its native scope was replaced', async () => {
  let finish;
  mocks.proposals.update.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await mountPage();
  await button('Solicitar aprovação').trigger('click');
  authority.role = 'agent';
  await flushPromises();
  finish({ data: record() });
  await flushPromises();
  expect(mocks.proposals.requestApproval).not.toHaveBeenCalled();
  expect(wrapper.find('aside').exists()).toBe(false);
});

it('does not resurrect an asynchronously opening creation form after native membership changed', async () => {
  let finish;
  mocks.deals.list.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await mountPage({ new: '1' });
  authority.accounts = [{ id: 1, role: 'agent', custom_role_id: 44 }];
  await flushPromises();
  finish({ data: [{ id: 9, title: 'Synthetic former membership deal' }] });
  await flushPromises();
  expect(wrapper.text()).not.toContain('Criar proposta');
  expect(mocks.proposals.create).not.toHaveBeenCalled();
});

it('preserves the native prior-account draft without writing its edited notes into another actors draft namespace', async () => {
  await mountPage();
  await wrapper
    .findAll('aside textarea')[1]
    .setValue('Synthetic private preserved draft');
  vi.advanceTimersByTime(350);
  const previousKey = 'jrc:draft:account:1:user:25:crm:proposal_edit:1';
  expect(sessionStorage.getItem(previousKey)).toContain(
    'Synthetic private preserved draft'
  );
  authority.id = 99;
  mocks.route.params.accountId = '2';
  await flushPromises();
  expect(sessionStorage.getItem(previousKey)).toContain(
    'Synthetic private preserved draft'
  );
  const otherDrafts = Object.keys(sessionStorage)
    .filter(key => key !== previousKey)
    .map(key => sessionStorage.getItem(key));
  expect(
    otherDrafts.some(value =>
      value.includes('Synthetic private preserved draft')
    )
  ).toBe(false);
  expect(wrapper.find('aside').exists()).toBe(false);
});

it('ignores a pending PDF after the proposal view is unmounted', async () => {
  let finish;
  mocks.proposals.pdf.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await mountPage();
  await button('Baixar PDF').trigger('click');
  wrapper.unmount();
  wrapper = null;
  finish({ data: new Blob(['%PDF synthetic disposed']) });
  await flushPromises();
  expect(download).not.toHaveBeenCalled();
});

it('does not save provisional financial defaults or request approval while its native detail is loading', async () => {
  let finish;
  mocks.proposals.show.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await mountPage();
  const approval = button('Solicitar aprovação');
  expect(approval.element.disabled).toBe(true);
  await approval.trigger('click');
  expect(mocks.proposals.update).not.toHaveBeenCalled();
  expect(mocks.proposals.requestApproval).not.toHaveBeenCalled();
  finish({ data: record() });
  await flushPromises();
  expect(button('Solicitar aprovação').element.disabled).toBe(false);
});

it('preserves an unsaved proposal during native presence refresh and still invalidates changed access scopes', async () => {
  await mountPage();
  await wrapper
    .findAll('aside textarea')[1]
    .setValue('Synthetic continuing commercial draft');
  const requests = mocks.proposals.show.mock.calls.length;
  authority.accounts[0].availability_status = 'offline';
  authority.accounts[0].active_at = '2026-11-07T10:00:00Z';
  await flushPromises();
  expect(wrapper.find('aside').exists()).toBe(true);
  expect(wrapper.findAll('aside textarea')[1].element.value).toBe(
    'Synthetic continuing commercial draft'
  );
  expect(mocks.proposals.show).toHaveBeenCalledTimes(requests);
  authority.accounts[0].custom_role_id = 7;
  await flushPromises();
  expect(wrapper.find('aside').exists()).toBe(false);
});
