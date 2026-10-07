import { shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { directive as onClickaway } from 'vue3-click-away';
import { useRoute, useRouter } from 'vue-router';
import ContactsIndex from '../ContactsIndex.vue';
import ContactListHeaderWrapper from 'dashboard/components-next/Contacts/ContactsHeader/ContactListHeaderWrapper.vue';
import ContactHeader from 'dashboard/components-next/Contacts/ContactsHeader/ContactHeader.vue';

vi.mock('vue-router', () => ({ useRoute: vi.fn(), useRouter: vi.fn() }));
vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
  useTrack: vi.fn(),
}));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ checkPermissions: () => true }),
}));
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
  const page = stubs =>
    shallowMount(ContactsIndex, {
      global: {
        stubs,
        directives: { 'on-clickaway': onClickaway },
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

  it('keeps a full API page and its pagination inside the keyboard accessible scroll region', async () => {
    store.getters['contacts/getContactsList'] = Array.from(
      { length: 15 },
      (_, index) => ({ id: index + 1, name: `Contact ${index + 1}` })
    );
    wrapper = page();
    await flushPromises();
    const region = wrapper.get('[role="region"][tabindex="0"]');
    expect(region.attributes('aria-label')).toBe('Contact list');
    expect(region.findAll('tbody tr')).toHaveLength(15);
    expect(region.findAll('tbody tr').at(-1).text()).toContain('Contact 15');
    expect(region.element.contains(button('Próxima').element)).toBe(true);
    store.dispatch.mockImplementationOnce(async () => {
      store.getters['contacts/getContactsList'] = [
        { id: 16, name: 'Contact 16' },
      ];
      store.getters['contacts/getMeta'] = { count: 16, currentPage: 2 };
      return true;
    });
    await button('Próxima').trigger('click');
    await flushPromises();
    expect(region.findAll('tbody tr')).toHaveLength(1);
    expect(region.get('tbody tr').text()).toContain('Contact 16');
    expect(button('Próxima').element.disabled).toBe(true);
    expect(button('Anterior').element.disabled).toBe(false);
  });

  it('does not present availability as commercial status or fabricated monthly metrics', async () => {
    store.getters['contacts/getContactsList'] = [
      {
        id: 42,
        name: 'Example',
        availabilityStatus: 'online',
        lastActivityAt: 1731608270,
      },
    ];
    wrapper = page();
    await flushPromises();
    const row = wrapper.get('tbody tr');
    expect(row.text()).toContain('Online');
    expect(row.text()).toContain('14/11/2024');
    expect(row.text()).not.toContain('JRC ADM');
    expect(row.text()).not.toContain('Agora');
    expect(wrapper.text().match(/Metric unavailable/g)).toHaveLength(3);
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

  it('connects search, sort, native filters and clear to contact list requests', async () => {
    wrapper = page();
    await flushPromises();
    const header = wrapper.getComponent(ContactListHeaderWrapper);
    header.vm.$emit('search', 'Example');
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith(
      'contacts/search',
      expect.objectContaining({ search: 'Example', page: 1 })
    );
    header.vm.$emit('update:sort', { sort: 'name', order: '-' });
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith(
      'contacts/get',
      expect.objectContaining({ sortAttr: '-name', page: 1 })
    );
    const queryPayload = {
      payload: [
        {
          attribute_key: 'name',
          filter_operator: 'equal_to',
          values: ['Example'],
        },
      ],
    };
    store.getters['contacts/getAppliedContactFilters'] = queryPayload.payload;
    header.vm.$emit('applyFilter', queryPayload);
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith(
      'contacts/filter',
      expect.objectContaining({ queryPayload, page: 1, sortAttr: '-name' })
    );
    header.vm.$emit('clearFilters');
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith('contacts/clearContactFilters');
  });

  it('opens native create/import dialogs and dispatches their payloads through the existing store', async () => {
    const openCreate = vi.fn();
    const openImport = vi.fn();
    const createSuccess = vi.fn();
    const closeImport = vi.fn();
    const openExport = vi.fn();
    wrapper = page({
      ContactListHeaderWrapper: false,
      ContactsHeader: false,
      ContactHeader: false,
      ContactMoreActions: false,
      Button: false,
      CreateNewContactDialog: {
        name: 'CreateNewContactDialog',
        template: '<div />',
        setup: () => ({
          open: openCreate,
          dialogRef: { open: openCreate },
          onSuccess: createSuccess,
        }),
      },
      ContactImportDialog: {
        name: 'ContactImportDialog',
        template: '<div />',
        setup: () => ({ dialogRef: { open: openImport, close: closeImport } }),
      },
      ContactExportDialog: {
        name: 'ContactExportDialog',
        template: '<div />',
        setup: () => ({ dialogRef: { open: openExport } }),
      },
    });
    await flushPromises();
    const header = wrapper.getComponent(ContactHeader);
    await button(
      wrapper.vm.$t(
        'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.ADD_CONTACT'
      )
    ).trigger('click');
    await button(
      wrapper.vm.$t(
        'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.IMPORT_CONTACT'
      )
    ).trigger('click');
    expect(openCreate).toHaveBeenCalledOnce();
    expect(openImport).toHaveBeenCalledOnce();
    const more = header.getComponent({ name: 'ContactMoreActions' });
    await more.get('button').trigger('click');
    more
      .getComponent({ name: 'DropdownMenu' })
      .vm.$emit('action', { action: 'export' });
    expect(openExport).toHaveBeenCalledOnce();
    const contact = { name: 'New contact', email: 'new@example.test' };
    wrapper
      .getComponent({ name: 'CreateNewContactDialog' })
      .vm.$emit('create', contact);
    const file = new File(
      ['name,email\nExample,new@example.test'],
      'contacts.csv',
      { type: 'text/csv' }
    );
    wrapper
      .getComponent({ name: 'ContactImportDialog' })
      .vm.$emit('import', file);
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith('contacts/create', contact);
    expect(store.dispatch).toHaveBeenCalledWith('contacts/import', file);
    expect(createSuccess).toHaveBeenCalledOnce();
    expect(closeImport).toHaveBeenCalledOnce();
    const query = { payload: [], label: '' };
    wrapper
      .getComponent({ name: 'ContactExportDialog' })
      .vm.$emit('export', query);
    await flushPromises();
    expect(store.dispatch).toHaveBeenCalledWith('contacts/export', query);
  });

  it('disables unsupported relationship views and actions with an explanation', async () => {
    wrapper = page();
    await flushPromises();
    expect(button('Pessoas').element.disabled).toBe(true);
    expect(button('Empresas').element.disabled).toBe(true);
    expect(button('Agenda').element.disabled).toBe(true);
    expect(button('Agenda').attributes('title')).toBe(
      'This action is not available in this view.'
    );
    expect(wrapper.text()).toContain(
      'The disabled views and actions are not available in this contact list.'
    );
  });

  it('closes contact details and reopens them only when a row is selected', async () => {
    wrapper = page();
    await flushPromises();
    await wrapper
      .get('button[aria-label="Close contact details"]')
      .trigger('click');
    expect(wrapper.findComponent({ name: 'ContactLeadAction' }).exists()).toBe(
      false
    );
    await wrapper.get('tbody tr').trigger('click');
    expect(wrapper.findComponent({ name: 'ContactLeadAction' }).exists()).toBe(
      true
    );
  });
});
