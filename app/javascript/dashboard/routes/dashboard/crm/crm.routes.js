import { frontendURL } from 'dashboard/helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import store from 'dashboard/store';

const CrmLayout = () => import('./CrmLayout.vue');
const CrmDashboardView = () => import('./views/dashboard/CrmDashboardView.vue');
const ReportsView = () => import('./views/reports/ReportsView.vue');
const LeadsIndex = () => import('./views/leads/LeadsIndex.vue');
const DealsIndex = () => import('./views/deals/DealsIndex.vue');
const DealsFunnelKanban = () =>
  import('./components/kanban/DealsFunnelKanban.vue');
const WalletView = () => import('./views/wallet/WalletView.vue');
const ActivitiesIndex = () => import('./views/activities/ActivitiesIndex.vue');
const CalendarView = () => import('./views/calendar/CalendarView.vue');
const ProductsIndex = () => import('./views/products/ProductsIndex.vue');
const ProposalsIndex = () => import('./views/proposals/ProposalsIndex.vue');

const SalesOrdersView = () => import('./views/orders/SalesOrdersView.vue');
const SalesOrderWizard = () => import('./views/orders/SalesOrderWizard.vue');
const ContractsView = () => import('./views/contracts/ContractsView.vue');
const ContractWizard = () => import('./views/contracts/ContractWizard.vue');
const ContractTemplates = () =>
  import('./views/contracts/ContractTemplates.vue');
const GoalsView = () => import('./views/goals/GoalsView.vue');
const CommissionsView = () => import('./views/commissions/CommissionsView.vue');
const Customer360View = () => import('./views/customers/Customer360View.vue');
const BackofficeView = () => import('./views/backoffice/BackofficeView.vue');
const ManagementView = () => import('./views/management/ManagementView.vue');
const CrmSettingsView = () => import('./views/settings/CrmSettingsView.vue');

const meta = {
  featureFlag: FEATURE_FLAGS.JRC_CRM,
  permissions: ['administrator', 'agent', 'custom_role'],
};

const ensureCrmEnabled = async to => {
  await store.dispatch('accounts/get', { silent: true });
  const enabled = store.getters['accounts/isFeatureEnabledonAccount'](
    Number(to.params.accountId),
    FEATURE_FLAGS.JRC_CRM
  );
  const currentAccount = store.getters.getCurrentAccount || {};
  const hasUserAccess = currentAccount.permissions?.includes('jrc_crm');
  return enabled && hasUserAccess
    ? true
    : frontendURL(`accounts/${to.params.accountId}/dashboard`);
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/crm'),
      component: CrmLayout,
      meta,
      beforeEnter: ensureCrmEnabled,
      children: [
        { path: '', redirect: { name: 'crm_dashboard' } },
        {
          path: 'dashboard',
          name: 'crm_dashboard',
          component: CrmDashboardView,
          meta,
        },
        {
          path: 'indicators',
          name: 'crm_indicators',
          component: ReportsView,
          meta,
        },
        { path: 'leads', name: 'crm_leads', component: LeadsIndex, meta },
        { path: 'deals', name: 'crm_deals', component: DealsIndex, meta },
        {
          path: 'funnel',
          name: 'crm_funnel',
          component: DealsFunnelKanban,
          meta,
        },
        { path: 'wallet', name: 'crm_wallet', component: WalletView, meta },
        {
          path: 'activities',
          name: 'crm_activities',
          component: ActivitiesIndex,
          meta,
        },
        {
          path: 'calendar',
          name: 'crm_calendar',
          component: CalendarView,
          meta,
        },
        {
          path: 'products',
          name: 'crm_products',
          component: ProductsIndex,
          meta,
        },
        {
          path: 'proposals',
          name: 'crm_proposals',
          component: ProposalsIndex,
          meta,
        },
        {
          path: 'orders',
          name: 'crm_orders',
          component: SalesOrdersView,
          meta,
        },
        {
          path: 'orders/new',
          name: 'crm_order_new',
          component: SalesOrderWizard,
          meta,
        },
        {
          path: 'contracts',
          name: 'crm_contracts',
          component: ContractsView,
          meta,
        },
        {
          path: 'contracts/new',
          name: 'crm_contract_new',
          component: ContractWizard,
          meta,
        },
        {
          path: 'contracts/templates',
          name: 'crm_contract_templates',
          component: ContractTemplates,
          meta,
        },
        { path: 'management', name: 'crm_management', component: ManagementView, meta: { ...meta, permissions: ['administrator'] } },
        { path: 'settings', name: 'crm_settings', component: CrmSettingsView, meta: { ...meta, permissions: ['administrator'] } },
        { path: 'goals', name: 'crm_goals', component: GoalsView, meta },
        {
          path: 'commissions/:section?',
          name: 'crm_commissions',
          component: CommissionsView,
          meta,
        },
        {
          path: 'backoffice/:section?',
          name: 'crm_backoffice',
          component: BackofficeView,
          meta,
        },
        {
          path: 'customers/:customerId',
          name: 'crm_customer_360',
          component: Customer360View,
          meta,
        },
      ],
    },
  ],
};
