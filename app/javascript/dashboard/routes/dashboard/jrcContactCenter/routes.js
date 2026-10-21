import { frontendURL } from 'dashboard/helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const baseMeta = {
  featureFlag: FEATURE_FLAGS.JRC_CONTACT_CENTER,
  permissions: ['administrator', 'agent', 'jrc_contact_center_view'],
};

const supervisorMeta = {
  ...baseMeta,
  permissions: ['administrator', 'jrc_contact_center_supervise'],
};

const managementMeta = {
  ...baseMeta,
  permissions: [
    'administrator',
    'jrc_contact_center_supervise',
    'jrc_contact_center_configure',
  ],
};

const reportsMeta = {
  ...baseMeta,
  permissions: [
    'administrator',
    'jrc_contact_center_reports',
    'jrc_contact_center_supervise',
  ],
};

const configureMeta = {
  ...baseMeta,
  permissions: ['administrator', 'jrc_contact_center_configure'],
};

const visualPage = screenKey => ({
  component: () => import('./views/visual/VisualExperiencePage.vue'),
  props: { screenKey },
});

export const routes = [
  {
    path: frontendURL('accounts/:accountId/contact-center'),
    component: () => import('./ContactCenterLayout.vue'),
    meta: baseMeta,
    children: [
      { path: '', redirect: { name: 'jrc_contact_center_cockpit' } },
      {
        path: 'operacao',
        name: 'jrc_contact_center_cockpit',
        component: () => import('./views/AgentCockpit.vue'),
        meta: baseMeta,
      },
      {
        path: 'chamada/:callId?',
        name: 'jrc_contact_center_call',
        component: () => import('./views/visual/CallExperiencePage.vue'),
        meta: baseMeta,
      },
      {
        path: 'pos-atendimento',
        name: 'jrc_contact_center_after_call',
        ...visualPage('afterCall'),
        meta: baseMeta,
      },
      {
        path: 'ocorrencias',
        name: 'jrc_contact_center_occurrences',
        component: () => import('./views/OccurrencesPage.vue'),
        meta: baseMeta,
      },
      {
        path: 'cliente-360/:customerId?',
        name: 'jrc_contact_center_customer_360',
        ...visualPage('customer360'),
        meta: baseMeta,
      },
      {
        path: 'supervisor',
        name: 'jrc_contact_center_supervisor',
        component: () => import('./views/SupervisorPage.vue'),
        meta: supervisorMeta,
      },
      {
        path: 'financeiro',
        name: 'jrc_contact_center_finance',
        ...visualPage('finance'),
        meta: managementMeta,
      },
      {
        path: 'coes',
        name: 'jrc_contact_center_coes',
        ...visualPage('coes'),
        meta: managementMeta,
      },
      {
        path: 'control-desk',
        name: 'jrc_contact_center_control_desk',
        component: () => import('./views/ControlDeskPage.vue'),
        meta: managementMeta,
      },
      {
        path: 'ura',
        name: 'jrc_contact_center_ivr',
        ...visualPage('ivrBuilder'),
        meta: configureMeta,
      },
      {
        path: 'ura/pedidos',
        name: 'jrc_contact_center_order_lookup',
        ...visualPage('orderLookup'),
        meta: managementMeta,
      },
      {
        path: 'pabx',
        name: 'jrc_contact_center_pabx',
        ...visualPage('pabxMonitor'),
        meta: managementMeta,
      },
      {
        path: 'gravacoes',
        name: 'jrc_contact_center_recordings',
        ...visualPage('recordings'),
        meta: reportsMeta,
      },
      {
        path: 'relatorios',
        name: 'jrc_contact_center_reports',
        component: () => import('./views/ReportsPage.vue'),
        meta: reportsMeta,
      },
      {
        path: 'pesquisas',
        name: 'jrc_contact_center_surveys',
        ...visualPage('surveys'),
        meta: reportsMeta,
      },
      {
        path: 'seguranca',
        name: 'jrc_contact_center_security',
        ...visualPage('security'),
        meta: configureMeta,
      },
      {
        path: 'migracao',
        name: 'jrc_contact_center_migration',
        ...visualPage('migration'),
        meta: configureMeta,
      },
      {
        path: 'configuracoes',
        name: 'jrc_contact_center_settings',
        component: () => import('./views/SettingsPage.vue'),
        meta: configureMeta,
      },
    ],
  },
];
