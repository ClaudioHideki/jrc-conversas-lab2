import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import { createMemoryHistory, createRouter } from 'vue-router';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import { contextPayload, identity } from './fixtures';
import { decodeContext } from '../helpers/contracts';
import { SERVICE_DESK_ROUTES, serviceDeskRouteName } from '../routeDefinitions';
const holder = vi.hoisted(() => ({ session: null }));
vi.mock('../composables/useServiceDesk', () => ({
  provideServiceDesk: () => holder.session,
}));
import Layout from '../ServiceDeskLayout.vue';
let wrapper;
let router;
beforeEach(async () => {
  const payload = contextPayload();
  payload.capabilities.reports = { index: true };
  payload.capabilities.services = { index: true };
  holder.session = {
    state: reactive({
      status: 'ready',
      context: decodeContext(payload, identity),
    }),
    accountId: ref('1'),
    userId: ref('7'),
    enabled: ref(true),
    operations: { state: reactive({ notice: null }) },
  };
  router = createRouter({
    history: createMemoryHistory(),
    routes: SERVICE_DESK_ROUTES.map(row => ({
      path: '/app/accounts/:accountId/service-desk/' + row.key,
      name: serviceDeskRouteName(row.key),
      meta: { serviceDeskScreen: row.key },
      component: { template: '<div />' },
    })),
  });
  await router.push({
    name: serviceDeskRouteName('overview'),
    params: { accountId: '1' },
  });
});
afterEach(() => wrapper?.unmount());
const render = () => {
  wrapper = mount(Layout, {
    global: {
      plugins: [
        router,
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: { Icon: true },
    },
  });
};
describe('Service Desk contextual navigation follows the reference and current grants', () => {
  it('keeps the native destinations in horizontal navigation without a second sidebar', () => {
    render();
    expect(wrapper.find('aside').exists()).toBe(false);
    expect(
      wrapper
        .get(
          `nav[aria-label="${messages.JRC_SERVICE_DESK.REDESIGN_LIST.navigation}"]`
        )
        .findAll('a')
        .some(link => link.text() === 'Visão geral')
    ).toBe(true);
    expect(wrapper.find('a[aria-current="page"]').text()).toBe('Visão geral');
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.GROUPS.governance
    );
  });
  it('removes an entry when the backend capability is revoked and clears navigation with the context', async () => {
    render();
    holder.session.state.context.capabilities.reports.index = false;
    holder.session.state.context.capabilities.services.index = false;
    await flushPromises();
    expect(wrapper.text()).not.toContain(
      messages.JRC_SERVICE_DESK.GROUPS.governance
    );
    expect(
      wrapper
        .findAll('a')
        .some(link => link.text() === messages.JRC_SERVICE_DESK.SCREENS.reports)
    ).toBe(false);
    holder.session.state.status = 'denied';
    holder.session.state.context = null;
    await flushPromises();
    expect(wrapper.find('nav').exists()).toBe(false);
  });
  it('keeps the ticket detail free of the module navigation and retains its breadcrumb', async () => {
    await router.push({
      name: serviceDeskRouteName('detail'),
      params: { accountId: '1' },
    });
    render();
    expect(
      wrapper
        .find(
          'nav[aria-label="' +
            messages.JRC_SERVICE_DESK.REDESIGN_LIST.navigation +
            '"]'
        )
        .exists()
    ).toBe(false);
    expect(wrapper.text()).toContain(messages.JRC_SERVICE_DESK.SCREENS.tickets);
  });
});
