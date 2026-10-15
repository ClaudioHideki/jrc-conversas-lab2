import { frontendURL } from 'dashboard/helper/URLHelper';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/flows/native'),
    name: 'jrc_flows_native',
    component: () => import('./NativeFlowModule.vue'),
    meta: { permissions: ['administrator', 'agent', 'custom_role'] },
  },
  {
    path: frontendURL('accounts/:accountId/flows'),
    name: 'jrc_flows',
    component: () => import('./FlowsWorkspace.vue'),
    meta: { permissions: ['administrator', 'agent', 'custom_role'] },
  },
];
