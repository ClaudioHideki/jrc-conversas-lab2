// Real components, production CSS and real authenticated Rails APIs. No API aliases.
import { createApp, h } from 'vue';
import { createStore } from 'vuex';
import { createRouter, createWebHistory, RouterView } from 'vue-router';
import { createI18n } from 'vue-i18n';
import axios from 'axios';
import ControlDeskPage from 'dashboard/routes/dashboard/jrcContactCenter/views/ControlDeskPage.vue';
import messages from 'dashboard/i18n/locale/pt_BR';
import '../../../../app/javascript/dashboard/assets/scss/app.scss';

window.chatwootConfig = {};
window.axios = axios;
Object.assign(axios.defaults.headers.common, window.__SYNTHETIC_AUTH__);
const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/app/accounts/:accountId/contact-center/control-desk',
      name: 'jrc_contact_center_control_desk',
      component: ControlDeskPage,
    },
    {
      path: '/app/accounts/:accountId/contact-center/control-desk/:section',
      name: 'jrc_contact_center_admin_section',
      component: ControlDeskPage,
    },
  ],
});
const store = createStore({ getters: { 'accounts/isRTL': () => false } });
const app = createApp({
  render: () =>
    h(
      'main',
      { class: 'min-h-screen min-w-0 bg-n-background text-n-slate-12' },
      [
        h(
          'p',
          { class: 'border-b border-n-weak px-4 py-2 text-xs' },
          'AMBIENTE SINTÉTICO · APIs Rails reais · Nenhum PABX conectado'
        ),
        h(RouterView),
      ]
    ),
});
router.isReady().then(() =>
  app
    .use(store)
    .use(
      createI18n({
        legacy: false,
        locale: 'pt_BR',
        messages: { pt_BR: messages },
      })
    )
    .mount('#app')
);
app.use(router);
