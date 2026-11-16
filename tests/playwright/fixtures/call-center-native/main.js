// Real components, production CSS and real authenticated Rails APIs. No API aliases.
import { createApp, h } from 'vue';
import { createStore } from 'vuex';
import { createRouter, createWebHistory, RouterView } from 'vue-router';
import { createI18n } from 'vue-i18n';
import axios from 'axios';
import ControlDeskPage from 'dashboard/routes/dashboard/jrcContactCenter/views/ControlDeskPage.vue';
import messages from 'dashboard/i18n/locale/pt_BR';
import english from 'dashboard/i18n/locale/en';
import customRole from 'dashboard/store/modules/customRole';
import ModalHeader from 'dashboard/components/ModalHeader.vue';
import SnackbarContainer from 'dashboard/components/SnackbarContainer.vue';
import CustomRolesHome from 'dashboard/routes/dashboard/settings/customRoles/Index.vue';
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
    {
      path: '/app/accounts/:accountId/settings/custom-roles/list',
      name: 'custom_roles_list',
      component: CustomRolesHome,
    },
  ],
});
const store = createStore({
  modules: { customRole },
  state: { nativeAccount: null },
  mutations: {
    setNativeAccount: (state, account) => {
      state.nativeAccount = account;
    },
  },
  getters: {
    'accounts/isRTL': () => false,
    getCurrentAccountId: () =>
      Number(router.currentRoute.value.params.accountId),
    'accounts/isFeatureEnabledonAccount': state => (id, feature) =>
      Number(state.nativeAccount?.id) === Number(id) &&
      state.nativeAccount.features[feature] === true,
  },
});
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
        h(SnackbarContainer),
      ]
    ),
});
app.component('woot-modal-header', ModalHeader);
router.isReady().then(async () => {
  const { data } = await axios.get(
    `/api/v1/accounts/${router.currentRoute.value.params.accountId}`
  );
  store.commit('setNativeAccount', data);
  app
    .use(store)
    .use(
      createI18n({
        legacy: false,
        locale: 'pt_BR',
        fallbackLocale: 'en',
        messages: { pt_BR: messages, en: english },
      })
    )
    .mount('#app');
});
app.use(router);
