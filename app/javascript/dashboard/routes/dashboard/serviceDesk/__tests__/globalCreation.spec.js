import { afterEach, describe, expect, it, vi } from 'vitest';
import { reactive, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createStore } from 'vuex';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import TicketListView from '../views/TicketListView.vue';
import TicketFormView from '../views/TicketFormView.vue';
import ScopeBar from '../components/ScopeBar.vue';
import { SERVICE_DESK_ROUTES, serviceDeskRouteName } from '../routeDefinitions';
import { contextPayload } from './fixtures';

const holder = vi.hoisted(() => ({ session: null }));
vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => holder.session,
}));
const wrappers = [];
const Button = {
  props: ['label', 'disabled'],
  template: '<button :disabled="disabled">{{ label }}</button>',
};
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
  holder.session = null;
});

async function render(accountId, allowed, component = TicketListView) {
  const context = contextPayload();
  context.account_id = accountId;
  context.units = context.units.slice(0, 1).map(unit => ({
    ...unit,
    account_id: accountId,
    initial_status: null,
    operator_company: { ...unit.operator_company, account_id: accountId },
    permissions: { create_ticket: allowed },
  }));
  holder.session = {
    state: reactive({ status: 'ready', context }),
    accountId: ref(accountId),
    userId: ref(context.user_id),
    enabled: ref(true),
    resource: () => ({ status: 'empty', record: null, items: [], meta: null }),
    load: vi.fn(),
    resetResource: vi.fn(),
    operations: {
      state: reactive({ revision: 0 }),
      mutation: () => ({ status: 'idle' }),
      dismissConfirmation: vi.fn(),
      cancel: vi.fn(),
      write: vi.fn(),
    },
  };
  const router = createRouter({
    history: createMemoryHistory(),
    routes: SERVICE_DESK_ROUTES.map(entry => ({
      path: `/app/accounts/:accountId/service-desk/${entry.path}`,
      name: serviceDeskRouteName(entry.key),
      component: { template: '<div />' },
    })),
  });
  const screen = component === TicketListView ? 'tickets' : 'new';
  await router.push({
    name: serviceDeskRouteName(screen),
    params: { accountId },
  });
  await router.isReady();
  const wrapper = mount(component, {
    props: { screen },
    global: {
      plugins: [
        router,
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
        createStore({
          getters: { 'accounts/isFeatureEnabledonAccount': () => () => false },
        }),
      ],
      stubs: {
        Button,
        LookupSelect: true,
        ServiceDefinitionSelect: true,
        CatalogueAnswers: true,
        TicketFilters: true,
        LiveKpis: true,
        PaginationFooter: true,
        TabBar: true,
      },
    },
  });
  wrappers.push(wrapper);
  await flushPromises();
  return { wrapper, router };
}

describe('Global Service Desk creation uses the authenticated Account', () => {
  it.each(['42', '73'])(
    'offers and navigates New ticket for enabled Account %s without assuming Account 1',
    async accountId => {
      const { wrapper, router } = await render(accountId, true);
      const button = wrapper
        .findAll('button')
        .find(item => item.text() === 'Novo chamado');
      expect(button).toBeDefined();
      await button.trigger('click');
      await flushPromises();
      expect(router.currentRoute.value.name).toBe(serviceDeskRouteName('new'));
      expect(router.currentRoute.value.params.accountId).toBe(accountId);
      expect(holder.session.operations.write).not.toHaveBeenCalled();
    }
  );

  it.each(['42', '73'])(
    'hides New ticket without the backend grant in Account %s',
    async accountId => {
      const { wrapper } = await render(accountId, false);
      expect(
        wrapper.findAll('button').some(item => item.text() === 'Novo chamado')
      ).toBe(false);
    }
  );

  it('keeps the existing form available and explains missing configuration without submitting or fabricating a status', async () => {
    const { wrapper } = await render('73', true, TicketFormView);
    wrapper.findComponent(ScopeBar).vm.$emit('update:unitId', '10');
    await flushPromises();
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.FORM.initial_status_required
    );
    await wrapper.find('form').trigger('submit');
    expect(holder.session.operations.write).not.toHaveBeenCalled();
    expect(holder.session.state.context.units[0].initial_status).toBeNull();
  });
});
