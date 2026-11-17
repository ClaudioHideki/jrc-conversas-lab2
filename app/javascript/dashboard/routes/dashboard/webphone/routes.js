import { frontendURL } from 'dashboard/helper/URLHelper';

const WebphonePage = () => import('./WebphonePage.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ramal/configuracao'),
    name: 'ramal_settings',
    component: () => import('./SipSettingsRoute.vue'),
    meta: { permissions: ['administrator', 'jrc_contact_center_administer'] },
  },
  {
    path: frontendURL('accounts/:accountId/ramal'),
    name: 'ramal_index',
    component: WebphonePage,
    meta: { permissions: ['administrator', 'agent', 'custom_role'] },
  },
];
