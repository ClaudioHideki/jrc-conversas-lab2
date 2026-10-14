import { frontendURL } from 'dashboard/helper/URLHelper';
export const routes = [
  {
    path: frontendURL('accounts/:accountId/operator'),
    name: 'jrc_operator',
    component: () => import('./OperatorPage.vue'),
    meta: {
      featureFlag: 'jrc_operator',
      permissions: ['administrator', 'agent', 'custom_role'],
    },
  },
];
