import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { beforeEach, expect, it, vi } from 'vitest';
import { createI18n } from 'vue-i18n';
import Action from './MasterTicketAction.vue';
import messages from 'dashboard/i18n/locale/en/crm.json';
const mocks = vi.hoisted(() => ({ state: null, context: vi.fn() }));
vi.mock('dashboard/api/serviceDesk', () => ({ default: mocks }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => computed(() => mocks.state.user),
}));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => JSON.stringify(mocks.state)),
    canAccess: computed(() => mocks.state.allowed),
    accountScopedRoute: (name, params, query) => ({
      name,
      params: { ...params, accountId: mocks.state.account },
      query,
    }),
  }),
}));
const RouterLink = { props: ['to'], template: '<a><slot /></a>' };
const render = () =>
  mount(Action, {
    props: { companyId: 80, contactId: 33 },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
      stubs: { RouterLink },
    },
  });
beforeEach(() => {
  mocks.state = reactive({ account: '1', user: '7', allowed: true });
  mocks.context.mockReset().mockResolvedValue({
    account_id: '1',
    user_id: '7',
    available: true,
    effective_permissions: ['jrc_service_desk_customers_view'],
    units: [{ permissions: { create_ticket: true } }],
  });
});
it('links to the native form with customer pointers and no authorization identifiers', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.findComponent(RouterLink).props('to')).toEqual({
    name: 'jrc_service_desk_new',
    params: { accountId: '1' },
    query: { master_company_id: 80, master_contact_id: 33 },
  });
  wrapper.unmount();
});
it('hides the action without native create permission', async () => {
  mocks.context.mockResolvedValue({
    account_id: '1',
    user_id: '7',
    available: true,
    effective_permissions: ['jrc_service_desk_customers_view'],
    units: [{ permissions: { create_ticket: false } }],
  });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.find('a').exists()).toBe(false);
  wrapper.unmount();
});
it('does not revive a stale action when account or role changes', async () => {
  let finish;
  mocks.context.mockImplementation(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render();
  mocks.state.allowed = false;
  await flushPromises();
  finish({
    account_id: '1',
    user_id: '7',
    available: true,
    effective_permissions: ['jrc_service_desk_customers_view'],
    units: [{ permissions: { create_ticket: true } }],
  });
  await flushPromises();
  expect(wrapper.find('a').exists()).toBe(false);
  wrapper.unmount();
});
