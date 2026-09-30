import { config, mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createI18n } from 'vue-i18n';
import Dashboard from 'dashboard/routes/dashboard/Dashboard.vue';
import dashboardRoutes from 'dashboard/routes/dashboard/dashboard.routes';
import GlobalQuickActions from '../GlobalQuickActions.vue';
import ptBR from 'dashboard/i18n/locale/pt_BR';

vi.mock('dashboard/routes', () => ({
  router: { push: vi.fn(), resolve: vi.fn() },
}));

const state = vi.hoisted(() => ({
  width: null,
  full: null,
  identity: null,
  actions: null,
}));
vi.mock('@vueuse/core', async importOriginal => ({
  ...(await importOriginal()),
  useWindowSize: () => ({ width: state.width }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: { previously_used_conversation_display_type: 'expanded' },
    updateUISettings: vi.fn(),
  }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: state.identity }),
}));
vi.mock('dashboard/stores/calls', () => ({
  useCallsStore: () => ({ hasActiveCall: false, hasIncomingCall: false }),
}));
vi.mock('dashboard/routes/dashboard/webphone/useSipWebphone', () => ({
  useSipWebphone: () => ({
    initialize: vi.fn(),
    shutdown: vi.fn(),
    hasCall: { value: false },
  }),
}));
vi.mock('dashboard/components-next/jrcCopilot/useJrcCopilot', () => ({
  useJrcCopilot: () => ({ isFull: state.full, openQuick: vi.fn() }),
}));
vi.mock('../useQuickActionAccess', () => ({
  useQuickActionAccess: () => ({
    actions: state.actions,
    accountId: state.identity,
    userId: { value: 7 },
  }),
}));
vi.mock('dashboard/store', () => ({
  default: { getters: {}, commit: vi.fn(), dispatch: vi.fn() },
}));
vi.mock('next/sidebar/Sidebar.vue', () => ({
  default: {
    template:
      '<div data-left-sidebar class="hidden w-64 shrink-0 bg-n-blue-9 lg:block" />',
  },
}));
vi.mock('dashboard/components/widgets/modal/WootKeyShortcutModal.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('dashboard/components/app/AddAccountModal.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('dashboard/routes/dashboard/upgrade/UpgradePage.vue', () => ({
  default: {
    setup: () => ({ shouldShowUpgradePage: false }),
    template: '<div />',
  },
}));
vi.mock('dashboard/components-next/jrcCopilot/JrcCopilotPanel.vue', () => ({
  default: { template: '<div data-nico-panel />' },
}));
vi.mock('dashboard/components-next/jrcCopilot/JrcCopilotLauncher.vue', () => ({
  default: {
    props: ['docked'],
    template:
      '<button data-nico-launcher class="size-14 shrink-0">NICO</button>',
  },
}));
vi.mock('dashboard/components-next/sidebar/MobileSidebarLauncher.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('dashboard/components-next/layout/JrcTopBar.vue', () => ({
  default: {
    template:
      '<header class="h-16 shrink-0 bg-n-solid-2">JRC Conversas</header>',
  },
}));
vi.mock('dashboard/routes/dashboard/webphone/SipCallWidget.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('dashboard/routes/dashboard/commands/commandbar.vue', () => ({
  __esModule: true,
  default: { template: '<div />' },
}));
vi.mock(
  'dashboard/components-next/Contacts/ContactsForm/CreateNewContactDialog.vue',
  () => ({ default: { template: '<div />' } })
);

// Real production route hierarchy, with only page bodies and guards replaced here.
// Authorization is exercised separately; this suite verifies the authenticated shell persists.
const placeholder = {
  template:
    '<div data-page class="flex h-full min-h-0 min-w-0"><main data-conversation class="min-w-0 flex-1 overflow-auto bg-n-surface-1">Página do módulo<router-view /></main><aside data-contact-panel class="w-64 max-w-[40%] shrink-0 overflow-auto bg-n-solid-2">Painel do contato</aside></div>',
};
const presentationOnly = routes =>
  routes.map(
    ({ beforeEnter, redirect, component, components, children, ...route }) => ({
      ...route,
      component: component === Dashboard ? Dashboard : placeholder,
      ...(children ? { children: presentationOnly(children) } : {}),
    })
  );

describe('Quick actions in the real authenticated route shell', () => {
  let wrapper;
  let router;
  const plugins = config.global.plugins;
  beforeEach(async () => {
    config.global.plugins = [];
    state.width = ref(1600);
    state.full = ref(false);
    state.identity = ref(1);
    state.actions = ref([
      {
        key: 'CONTACT',
        command: 'contact',
        icon: 'i-lucide-user-round-plus',
        tone: 'blue',
      },
      {
        key: 'CALL',
        to: { name: 'ramal_index', params: { accountId: 1 } },
        icon: 'i-lucide-phone-call',
        tone: 'teal',
      },
      {
        key: 'LEAD',
        to: {
          name: 'crm_leads',
          params: { accountId: 1 },
          query: { new: '1' },
        },
        icon: 'i-lucide-chart-no-axes-combined',
        tone: 'violet',
      },
      {
        key: 'DEAL',
        to: {
          name: 'crm_deals',
          params: { accountId: 1 },
          query: { new: '1' },
        },
        icon: 'i-lucide-target',
        tone: 'violet',
      },
      {
        key: 'ACTIVITY',
        to: {
          name: 'crm_activities',
          params: { accountId: 1 },
          query: { new: '1' },
        },
        icon: 'i-lucide-calendar-plus',
        tone: 'blue',
      },
      {
        key: 'NICO',
        command: 'nico',
        icon: 'i-lucide-sparkles',
        tone: 'violet',
      },
    ]);
    router = createRouter({
      history: createMemoryHistory(),
      routes: presentationOnly(dashboardRoutes.routes),
    });
    await router.push('/app/accounts/1/dashboard');
    wrapper = mount(
      { template: '<router-view />' },
      {
        global: {
          plugins: [
            router,
            createStore({}),
            createI18n({
              legacy: false,
              locale: 'pt_BR',
              messages: { pt_BR: ptBR },
            }),
          ],
        },
      }
    );
    await flushPromises();
  });
  afterEach(() => {
    wrapper?.unmount();
    config.global.plugins = plugins;
  });

  it.each([
    '/dashboard',
    '/cockpit',
    '/conversations/51',
    '/emails',
    '/chamadas',
    '/ramal',
    '/calls',
    '/contacts',
    '/service-desk/tickets',
    '/crm/leads',
    '/projetos',
    '/minha-agenda',
    '/inteligencia/agentes',
    '/copiloto-jrc',
    '/settings/general',
    '/jrc-campanhas',
    '/reports/overview',
  ])(
    'keeps one global rail and the same instance when navigating to %s',
    async path => {
      const rail = wrapper.get('[data-global-quick-actions]').element;
      await router.push(`/app/accounts/1${path}`);
      await flushPromises();
      expect(
        router.currentRoute.value.matched.some(
          record => record.components?.default === Dashboard
        )
      ).toBe(true);
      expect(wrapper.findAll('[data-global-quick-actions]')).toHaveLength(1);
      expect(wrapper.get('[data-global-quick-actions]').element === rail).toBe(
        true
      );
      expect(wrapper.findAll('[data-nico-launcher]')).toHaveLength(1);
      expect(
        wrapper.findComponent(GlobalQuickActions).find('[data-page]').exists()
      ).toBe(false);
    }
  );

  it('keeps the rail outside the page/panel container and keeps it available with full NICO open', async () => {
    const rail = wrapper.get('[data-global-quick-actions]');
    const center = rail.element.previousElementSibling;
    expect(center.contains(wrapper.get('[data-contact-panel]').element)).toBe(
      true
    );
    expect(center.contains(rail.element)).toBe(false);
    expect(center.classList.contains('min-w-0')).toBe(true);
    expect(rail.classes()).toContain('shrink-0');
    state.full.value = true;
    await flushPromises();
    expect(wrapper.findAll('[data-global-quick-actions]')).toHaveLength(1);
  });

  it('all named routes nested in the account shell inherit the rail, including settings and reports', () => {
    const routes = router
      .getRoutes()
      .filter(
        route => route.name && route.path.startsWith('/app/accounts/:accountId')
      );
    expect(routes.length).toBeGreaterThan(50);
    routes.forEach(route => {
      const resolved = router.resolve({
        name: route.name,
        params: Object.fromEntries(
          [...route.path.matchAll(/:([A-Za-z_]+)/g)].map(match => [
            match[1],
            '1',
          ])
        ),
      });
      if (
        [
          'onboarding_account_details',
          'onboarding_inbox_setup',
          'account_suspended',
        ].includes(route.name)
      )
        return;
      expect(
        resolved.matched.some(
          record => record.components?.default === Dashboard
        ),
        String(route.name)
      ).toBe(true);
    });
  });
});
