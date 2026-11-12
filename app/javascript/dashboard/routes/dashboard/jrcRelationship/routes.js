import { frontendURL } from 'dashboard/helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { SCREENS } from './definitions';
const meta = {
  featureFlag: FEATURE_FLAGS.JRC_RELATIONSHIP,
  permissions: ['administrator', 'agent', 'jrc_relationship_view'],
};
export const routes = [
  {
    path: frontendURL('accounts/:accountId/relationship'),
    component: () => import('./RelationshipLayout.vue'),
    meta,
    children: [
      { path: '', redirect: { name: 'jrc_relationship_overview' } },
      ...SCREENS.map(screen => ({
        path: screen,
        name: `jrc_relationship_${screen}`,
        meta,
        component: () => {
          if (['overview', 'actions'].includes(screen))
            return import('./AnalystWorkspace.vue');
          if (screen === 'customers') return import('./CustomerWorkspace.vue');
          if (screen === 'portfolio') return import('./PortfolioWorkspace.vue');
          return import('./ModulePage.vue');
        },
        props: { screen: screen === 'actions_advanced' ? 'actions' : screen },
      })),
    ],
  },
];
