// Isolated visual fixture: no credentials, provider, real phone or network mutation.
import { createApp, h, ref } from 'vue';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createI18n } from 'vue-i18n';
import ConnectionsPage from 'dashboard/routes/dashboard/jrcBroker/ConnectionsPage.vue';
import en from 'dashboard/i18n/locale/en/jrcBroker.json';
import pt from 'dashboard/i18n/locale/pt_BR/jrcBroker.json';
import '../../../../app/javascript/dashboard/assets/scss/app.scss';

const inboxes = [
  { id: 701, name: 'Atendimento — demonstração', jrc_broker_bound: true },
  { id: 702, name: 'Comercial — demonstração', jrc_broker_bound: true },
];
const teams = [
  { id: 41, name: 'Suporte' },
  { id: 42, name: 'Comercial' },
];
const policies = new Map([
  [
    701,
    {
      enabled: true,
      mode: 'round_robin',
      team_ids: [41, 42],
      max_open: 10,
      capacity_enabled: true,
      respect_availability: true,
      waiting_enabled: true,
      schedule: 'always',
      fallback: 'waiting',
      fallback_team_id: null,
    },
  ],
]);
const now = () => new Date().toISOString();
const pairingRequests = ref(0);
const isAgent = new URLSearchParams(location.search).get('role') === 'agent';
window.chatwootConfig = { jrcBrokerEnabled: true };
window.axios = async ({ method, url, data }) => {
  if (!url.startsWith('/api/v1/accounts/9001/'))
    throw new Error('Fixture refused another account');
  const id = Number(url.match(/inboxes\/(\d+)/)?.[1]);
  if (url.endsWith('/inboxes')) return { data: { payload: inboxes } };
  if (url.endsWith('/assignment_policy'))
    return { data: { enabled: false, max_open: 10, inbox_ids: [] } };
  if (url.endsWith('/status'))
    return {
      data: {
        instanceStatus: id === 701 ? 'CONNECTED' : 'DISCONNECTED',
        integrationStatus: 'READY',
        transportStatus: 'UNVERIFIED',
        identityApproved: true,
        identityStatus: 'CONFIRMED',
        observedNumberSuffix: '0000',
        connectedAt: null,
        lastSyncAt: id === 701 ? now() : null,
        checkedAt: now(),
        allowedActions: isAgent
          ? ['status', 'pair']
          : ['status', 'pair', 'disconnect', 'manage'],
      },
    };
  if (url.endsWith('/distribution')) {
    if (method === 'put') policies.set(id, { ...data, effective_from: now() });
    return {
      data: {
        policy: policies.get(id) || null,
        teams,
        calendar: { enabled: false, timezone: 'America/Sao_Paulo' },
      },
    };
  }
  if (url.endsWith('/summary'))
    return {
      data: {
        inbox_id: id,
        metrics: isAgent
          ? null
          : {
              conversations_count: 12,
              avg_first_response_time: 95,
              avg_resolution_time: 1800,
              eligible_agents: null,
            },
      },
    };
  if (url.endsWith('/pair')) {
    pairingRequests.value += 1;
    return {
      data: {
        action: {
          type: 'PAIRING_CODE',
          code: 'DEMO-ONLY',
          expiresAt: new Date(Date.now() + 30000).toISOString(),
        },
      },
    };
  }
  if (url.includes('/history') || url.includes('/distribution-history'))
    return { data: { data: [], next_cursor: null } };
  if (url.endsWith('/configuration')) return { data: { id, name: data.name } };
  throw new Error(`No fixture for ${method} ${url}`);
};
const router = createRouter({
  history: createMemoryHistory(),
  routes: [
    {
      path: '/app/accounts/:accountId/whatsapp-connections',
      component: ConnectionsPage,
    },
  ],
});
await router.push('/app/accounts/9001/whatsapp-connections');
const store = createStore({
  getters: {
    getCurrentRole: () => (isAgent ? 'agent' : 'administrator'),
    'accounts/getAccount': () => () => ({
      id: 9001,
      features: { jrc_broker: true },
    }),
    'globalConfig/isOnChatwootCloud': () => false,
    'accounts/isFeatureEnabledonAccount': () => () => true,
  },
});
const app = createApp({
  render: () =>
    h('div', { class: 'h-screen flex flex-col bg-n-background' }, [
      h(
        'div',
        {
          class:
            'border-b border-n-weak bg-n-solid-1 px-6 py-3 text-xs text-n-slate-11',
        },
        [
          'LABORATÓRIO VISUAL · Dados sintéticos · Pareamentos simulados: ',
          h(
            'output',
            { 'data-testid': 'fixture-pair-requests' },
            String(pairingRequests.value)
          ),
        ]
      ),
      h(ConnectionsPage),
    ]),
});
app
  .use(store)
  .use(router)
  .use(
    createI18n({
      legacy: false,
      locale: 'pt_BR',
      fallbackLocale: 'en',
      messages: { en, pt_BR: pt },
    })
  )
  .mount('#app');
