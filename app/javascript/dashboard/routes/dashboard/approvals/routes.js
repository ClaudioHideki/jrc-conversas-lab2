import { frontendURL } from 'dashboard/helper/URLHelper';
export const APPROVAL_PAGES = [
  'policies',
  'inbox',
  'simulate',
  'delegations',
  'history',
  'own-delegations',
];
export const routes = [
  {
    path: frontendURL(
      'accounts/:accountId/approvals/:screen(policies|inbox|simulate|delegations|history|own-delegations)/:id?'
    ),
    name: 'jrc_approvals',
    component: () => import('./ApprovalsPage.vue'),
    meta: {
      featureFlag: 'jrc_approvals',
      permissions: ['administrator', 'agent', 'custom_role'],
    },
  },
];
