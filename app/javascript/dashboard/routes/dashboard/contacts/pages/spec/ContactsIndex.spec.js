import { shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import ContactsIndex from '../ContactsIndex.vue';

vi.mock('vue-router', () => ({ useRoute: vi.fn(), useRouter: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: { value: {} },
    updateUISettings: vi.fn(),
  }),
}));
vi.mock('@chatwoot/utils', async original => ({
  ...(await original()),
  debounce: fn => fn,
}));

describe('Relationship center pagination', () => {
  let store;
  let route;
  let wrapper;
  const page = () =>
    shallowMount(ContactsIndex, {
      global: {
        plugins: [
          {
            install(app) {
              app.config.globalProperties.$store = store;
            },
          },
        ],
      },
    });
  const button = label =>
    wrapper.findAll('button').find(item => item.text() === label);
  beforeEach(() => {
    route = reactive({
      name: 'contacts_dashboard_index',
      params: { accountId: '1' },
      query: { page: '1' },
    });
    useRoute.mockReturnValue(route);
    useRouter.mockReturnValue({ replace: vi.fn(), push: vi.fn() });
    store = {
      dispatch: vi.fn().mockResolvedValue(true),
      getters: reactive({
        'contacts/getContactsList': [{ id: 42, name: 'Cliente' }],
        'contacts/getMeta': { count: 31, currentPage: 1 },
        'contacts/getUIFlags': { isFetching: false },
        'customViews/getUIFlags': { isFetching: false },
        'customViews/getContactCustomViews': [],
        'contacts/getAppliedContactFilters': [],
        'accounts/isFeatureEnabledonAccount': () => true,
      }),
    };
  });
  afterEach(() => wrapper?.unmount());

  it('uses count for regular pagination, even without has_more', async () => {
    wrapper = page();
    await flushPromises();
    expect(button('Anterior').element.disabled).toBe(true);
    expect(button('Próxima').element.disabled).toBe(false);
    await button('Próxima').trigger('click');
    expect(store.dispatch).toHaveBeenCalledWith(
      'contacts/get',
      expect.objectContaining({ page: 2 })
    );
    store.getters['contacts/getMeta'].currentPage = 3;
    await flushPromises();
    expect(button('Próxima').element.disabled).toBe(true);
    await button('Anterior').trigger('click');
    expect(store.dispatch).toHaveBeenCalledWith(
      'contacts/get',
      expect.objectContaining({ page: 2 })
    );
  });

  it('retries the same search page on failure and does not skip records', async () => {
    route.query.search = 'Cliente';
    store.getters['contacts/getMeta'].hasMore = true;
    wrapper = page();
    await flushPromises();
    store.dispatch.mockResolvedValueOnce(false);
    await button('Carregar mais contatos').trigger('click');
    await flushPromises();
    expect(button('Carregar mais contatos').element.disabled).toBe(false);
    store.dispatch.mockImplementationOnce(async () => {
      store.getters['contacts/getMeta'].currentPage = 2;
      return true;
    });
    await button('Carregar mais contatos').trigger('click');
    await flushPromises();
    const appendCalls = store.dispatch.mock.calls.filter(
      ([, data]) => data?.append
    );
    expect(appendCalls.map(([, data]) => data.page)).toEqual([2, 2]);
    store.getters['contacts/getMeta'].hasMore = false;
    await flushPromises();
    expect(button('Carregar mais contatos')).toBeUndefined();
  });

  it('does not issue parallel continuation requests', async () => {
    route.query.search = 'Cliente';
    store.getters['contacts/getMeta'].hasMore = true;
    wrapper = page();
    await flushPromises();
    let finish;
    store.dispatch.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    await button('Carregar mais contatos').trigger('click');
    await button('Carregar mais contatos').trigger('click');
    expect(
      store.dispatch.mock.calls.filter(([, data]) => data?.append)
    ).toHaveLength(1);
    finish(false);
    await flushPromises();
  });

  it('does not mount the CRM action when the module is disabled', async () => {
    store.getters['accounts/isFeatureEnabledonAccount'] = () => false;
    wrapper = page();
    await flushPromises();
    expect(wrapper.findComponent({ name: 'ContactLeadAction' }).exists()).toBe(
      false
    );
  });
});
