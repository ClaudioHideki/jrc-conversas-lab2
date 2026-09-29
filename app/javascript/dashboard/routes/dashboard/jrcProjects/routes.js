import { frontendURL } from 'dashboard/helper/URLHelper';

const meta = { permissions: ['administrator', 'agent', 'custom_role'] };

export const routes = [
  {
    path: frontendURL('accounts/:accountId/projetos'),
    component: () => import('./ProjectsLayout.vue'),
    meta,
    children: [
      {
        path: '',
        name: 'jrc_projects_list',
        component: () => import('../jrcOperations/views/ProjectList.vue'),
        meta: { ...meta, operationKind: 'projects' },
      },
      {
        path: 'configuracoes',
        name: 'jrc_projects_settings',
        component: () => import('./views/ProjectSettings.vue'),
        meta,
      },
      {
        path: ':projectId',
        name: 'jrc_projects_detail',
        component: () => import('../jrcOperations/views/ProjectDetail.vue'),
        meta: { ...meta, operationKind: 'projects' },
      },
    ],
  },
];
