import { createMemoryHistory, createRouter } from 'vue-router';
import crmRoutes from '../../crm.routes';

const store = vi.hoisted(() => ({
  dispatch: vi.fn().mockResolvedValue(),
  getters: {
    'accounts/isFeatureEnabledonAccount': () => true,
    getCurrentUser: { accounts: [{ id: 1, permissions: ['jrc_crm'] }] },
  },
}));
vi.mock('dashboard/store', () => ({ default: store }));
const component = { template: '<RouterView />' };
const flattenComponents = route => ({
  ...route,
  ...(route.component ? { component } : {}),
  ...(route.children
    ? { children: route.children.map(flattenComponents) }
    : {}),
});

it.each([
  [
    '/app/accounts/1/crm/backoffice/requests?companyId=15',
    'crm_backoffice',
    '/app/accounts/1/backoffice/requests',
  ],
  [
    '/app/accounts/1/crm/backoffice/requests/7?tab=documents',
    'crm_backoffice_request',
    '/app/accounts/1/backoffice/requests/7',
  ],
])(
  'redirects old URLs and preserves filters without nesting the CRM layout',
  async (url, name, path) => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: crmRoutes.routes.map(flattenComponents),
    });
    await router.push(url);
    expect(router.currentRoute.value.name).toBe(name);
    expect(router.currentRoute.value.path).toBe(path);
    expect(router.currentRoute.value.matched).toHaveLength(1);
    expect(router.currentRoute.value.query).toEqual(
      url.includes('companyId') ? { companyId: '15' } : { tab: 'documents' }
    );
    expect(store.dispatch).toHaveBeenCalledWith('accounts/get', {
      silent: true,
    });
  }
);
