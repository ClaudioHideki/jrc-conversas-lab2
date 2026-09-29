import { frontendURL } from 'dashboard/helper/URLHelper';
export const routes = [
  {
    path: frontendURL('accounts/:accountId/minha-agenda'),
    name: 'jrc_operations_agenda',
    component: () => import('./views/AgendaPage.vue'),
    meta: { permissions: ['administrator', 'agent', 'custom_role'] },
  },
];
