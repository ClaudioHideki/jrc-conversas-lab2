import { frontendURL } from 'dashboard/helper/URLHelper';

const WebphonePage = () => import('./WebphonePage.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ramal/configuracao'),
    name: 'ramal_settings',
    component: () => import('./SipSettingsPage.vue'),
    meta: { permissions: ['administrator'] },
  },
  {
    path: frontendURL('accounts/:accountId/ramal'),
    name: 'ramal_index',
    component: WebphonePage,
    meta: { permissions: ['administrator', 'agent', 'custom_role'] },
  },
];
