import { frontendURL } from 'dashboard/helper/URLHelper';
export const APPROVAL_PAGES = [
  'policies',
  'inbox',
  'simulate',
  'delegations',
  'history',
];
export const routes = [
  {
    path: frontendURL(
      'accounts/:accountId/approvals/:screen(policies|inbox|simulate|delegations|history)/:id?'
    ),
    name: 'jrc_approvals',
    component: () => import('./ApprovalsPage.vue'),
    meta: {
      featureFlag: 'jrc_approvals',
      permissions: ['administrator', 'agent', 'custom_role'],
    },
  },
];
