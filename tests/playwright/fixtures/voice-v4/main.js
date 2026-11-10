// Real Vue components, isolated synthetic adapters. No SIP socket, credentials or external request.
import { createApp, h, ref } from 'vue';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createI18n } from 'vue-i18n';
import GlobalVoiceBar from 'dashboard/components-next/layout/GlobalVoiceBar.vue';
import HoyaInboxWorkspace from 'dashboard/routes/dashboard/inbox/HoyaInboxWorkspace.vue';
import { GLOBAL_VOICE_SHELL } from 'dashboard/routes/dashboard/webphone/voiceShell';
import { record, scenario } from './state';
import { context } from './api';
import ptBR from 'dashboard/i18n/locale/pt_BR';
import destinations from './destinations.json';
import '../../../../app/javascript/dashboard/assets/scss/app.scss';
window.chatwootConfig = {};
window.axios = Object.fromEntries(
  ['get', 'post', 'patch', 'delete'].map(method => [
    method,
    async () => {
      throw Error(`External request refused in fixture: ${method}`);
    },
  ])
);
const currentCall = ref(scenario !== 'idle' ? record.id : null);
const workspaceVisible = ref(true);
const currentConversation = ref(scenario !== 'idle' ? null : 9201);
const conversations = [
  {
    id: 9201,
    status: 'open',
    inbox_id: 31,
    account_id: 9001,
    meta: { sender: { id: 9200, name: 'Cliente sintético B' } },
  },
];
const router = createRouter({
  history: createMemoryHistory(),
  routes: [
    {
      path: '/app/accounts/:accountId/inbox-view/:type/:id',
      name: 'inbox_view_conversation',
      component: {
        template:
          '<article data-whatsapp-fixture class="p-5">Conversa WhatsApp do cliente sintético B</article>',
      },
    },
  ],
});
destinations.forEach(name =>
  router.addRoute({
    path: `/app/accounts/:accountId/fixture/${name}/:customerId?`,
    name,
    component: { template: '<article>Rota sintética</article>' },
  })
);
const initialNavigation = router.push(
  '/app/accounts/9001/inbox-view/call/9009'
);
const store = createStore({
  getters: {
    getCurrentUserID: () => 901,
    getSelectedChat: () => null,
    'accounts/isFeatureEnabledonAccount': () => () => false,
  },
});
const selectVoice = () => {
  workspaceVisible.value = true;
  currentCall.value = record.id;
  currentConversation.value = null;
};
const selectWhatsApp = () => {
  workspaceVisible.value = true;
  currentCall.value = null;
  currentConversation.value = 9201;
};
const app = createApp({
  render: () =>
    h('main', { class: 'flex h-screen min-h-0 flex-col bg-n-background' }, [
      h(
        'header',
        {
          class:
            'flex flex-wrap shrink-0 gap-3 border-b border-n-weak bg-n-solid-1 p-3 text-xs',
        },
        [
          h('strong', 'LABORATÓRIO SINTÉTICO · Voz V4 · Sem chamadas reais'),
          h(
            'button',
            { 'data-fixture-voice': '', onClick: selectVoice },
            'Abrir Voz'
          ),
          h(
            'button',
            { 'data-fixture-whatsapp': '', onClick: selectWhatsApp },
            'Abrir WhatsApp'
          ),
          h(
            'button',
            {
              'data-fixture-other-module': '',
              onClick: () => {
                workspaceVisible.value = false;
              },
            },
            'Abrir outro módulo'
          ),
        ]
      ),
      h(GlobalVoiceBar),
      workspaceVisible.value
        ? h(HoyaInboxWorkspace, {
            accountId: 9001,
            context,
            softphoneAccess: true,
            currentCallId: currentCall.value,
            currentConversationId: currentConversation.value,
            calls: scenario === 'idle' ? [] : [record],
            conversations,
            channels: [
              { key: 'voice', label: 'Voz' },
              { key: 'whatsapp', label: 'WhatsApp' },
            ],
            inboxFor: () => ({
              id: 31,
              name: 'WhatsApp — laboratório',
              channel_type: 'Channel::Whatsapp',
            }),
            onSelectCall: selectVoice,
            onSelectConversation: selectWhatsApp,
          })
        : h(
            'article',
            { 'data-fixture-module': '', class: 'p-5' },
            'Outro módulo — laboratório sintético'
          ),
    ]),
});
initialNavigation.then(() => {
  app
    .provide(GLOBAL_VOICE_SHELL, true)
    .use(store)
    .use(router)
    .use(
      createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } })
    )
    .mount('#app');
});
