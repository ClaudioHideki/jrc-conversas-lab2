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
import { routes as webphoneRoutes } from 'dashboard/routes/dashboard/webphone/routes';
import { routes as contactCenterRoutes } from 'dashboard/routes/dashboard/jrcContactCenter/routes';
import { validateLoggedInRoutes } from 'dashboard/helper/routeHelpers';
import '../../../../app/javascript/dashboard/assets/scss/app.scss';

const nativeNavigation = new URLSearchParams(window.location.search).has(
  'native_navigation'
);

const localIvrRoute = contactCenterRoutes[0].children.find(
  route => route.name === 'jrc_contact_center_ivr'
);
if (!localIvrRoute)
  throw new Error('Native IVR route missing from fixture source');

window.chatwootConfig = {};
window.axios = axios;
Object.assign(axios.defaults.headers.common, window.__SYNTHETIC_AUTH__);
const router = createRouter({
  history: createWebHistory(),
  routes: [
    ...(nativeNavigation ? contactCenterRoutes : []),
    {
      path: '/synthetic-access-denied',
      name: 'synthetic_access_denied',
      component: {
        template:
          '<p role="alert">Negado pela verificação nativa de rota no ambiente sintético.</p>',
      },
    },
    ...(nativeNavigation
      ? webphoneRoutes
      : webphoneRoutes.filter(route => route.name === 'ramal_settings')),
    ...(!nativeNavigation
      ? [
          {
            ...localIvrRoute,
            path: contactCenterRoutes[0].path + '/' + localIvrRoute.path,
          },
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
        ]
      : []),
    {
      path: '/app/accounts/:accountId/settings/custom-roles/list',
      name: 'custom_roles_list',
      component: CustomRolesHome,
    },
  ],
});
const store = createStore({
  modules: { customRole },
  state: { nativeAccount: null, nativeUser: {} },
  mutations: {
    setNativeAccount: (state, account) => {
      state.nativeAccount = account;
    },
    setNativeUser: (state, user) => {
      state.nativeUser = {
        id: user.id,
        name: user.name,
        type: user.type,
        ui_settings: user.ui_settings,
        accounts: user.accounts.map(account => ({
          id: account.id,
          status: account.status,
          role: account.role,
          permissions: account.permissions,
          custom_role_id: account.custom_role_id,
        })),
      };
    },
  },
  getters: {
    getCurrentUser: state => state.nativeUser,
    'accounts/isRTL': () => false,
    getCurrentAccountId: () =>
      Number(router.currentRoute.value.params.accountId),
    'accounts/isFeatureEnabledonAccount': state => (id, feature) =>
      Number(state.nativeAccount?.id) === Number(id) &&
      state.nativeAccount.features[feature] === true,
  },
});
// Native permission consumer and production layout, backed by fresh authenticated APIs.
router.beforeEach(async to => {
  if (
    !nativeNavigation &&
    !['ramal_settings', 'jrc_contact_center_ivr'].includes(to.name)
  )
    return true;
  if (to.name === 'synthetic_access_denied') return true;
  const [account, profile] = await Promise.all([
    axios.get(`/api/v1/accounts/${to.params.accountId}`),
    axios.get('/api/v1/profile'),
  ]);
  store.commit('setNativeAccount', account.data);
  store.commit('setNativeUser', profile.data);
  return validateLoggedInRoutes(to, store.getters.getCurrentUser)
    ? { name: 'synthetic_access_denied' }
    : true;
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
  if (!nativeNavigation && !store.state.nativeAccount) {
    const [account, profile] = await Promise.all([
      axios.get(
        `/api/v1/accounts/${router.currentRoute.value.params.accountId}`
      ),
      axios.get('/api/v1/profile'),
    ]);
    store.commit('setNativeAccount', account.data);
    store.commit('setNativeUser', profile.data);
  }
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
