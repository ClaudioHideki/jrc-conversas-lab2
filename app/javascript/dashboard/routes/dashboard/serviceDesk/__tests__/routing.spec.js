import { beforeEach, afterEach, describe, it, expect, vi } from 'vitest';
import { createRouter, createMemoryHistory } from 'vue-router';
import { contextPayload } from './fixtures.js';
import { SERVICE_DESK_ROUTES } from '../routeDefinitions.js';
const state = vi.hoisted(() => ({ account: { id: '1', features: { jrc_service_desk: false } } }));
vi.mock('dashboard/store', () => ({ default: { getters: { getCurrentUserID: '7', 'accounts/isFeatureEnabledonAccount': (id, key) => String(id) === String(state.account.id) && state.account.features[key] === true }, commit: (_type, value) => { state.account = value; } } }));
vi.mock('dashboard/helper/URLHelper', () => ({ frontendURL: path => `/app/${path}` }));
const contextMock = vi.hoisted(() => vi.fn());
vi.mock('dashboard/api/serviceDesk', () => ({ default: { context: contextMock } }));
import { routes } from '../routes.js';
let get;
const makeRouter = () => {
  const component = { template: '<div />' };
  // Exercise real route metadata and guards, replacing only lazy view rendering.
  return createRouter({ history: createMemoryHistory(), routes: [{ path: '/app/accounts/:accountId/dashboard', name: 'home', component }, ...routes.map(route => ({ ...route, component, children: route.children?.map(child => ({ ...child, component })) }))] });
};
beforeEach(() => { contextMock.mockReset(); contextMock.mockImplementation(async account => { const value = contextPayload(); value.account_id = String(account); value.units.forEach(unit => { unit.account_id = String(account); unit.operator_company.account_id = String(account); }); return value; }); state.account = { id: '1', features: { jrc_service_desk: false } }; get = vi.fn(async () => ({ data: state.account })); vi.stubGlobal('axios', { get }); });
afterEach(() => vi.unstubAllGlobals());
describe('Service Desk route registration and native Account feature gate', () => {
  it('all screens use only the existing Service Desk flag and own names', () => {
    const operationalRoute = routes.find(route => route.path === '/app/accounts/:accountId/service-desk');
    expect(operationalRoute.children).toHaveLength(SERVICE_DESK_ROUTES.length);
    for (const route of operationalRoute.children) {
      expect(route.name).toMatch(/^jrc_service_desk_/);
      expect(route.meta.featureFlag).toBe('jrc_service_desk');
      expect(route.beforeEnter).toBeTypeOf('function');
    }
  });
  it('flag disabled redirects deep links to the native home', async () => {
    const router = makeRouter();
    await router.push({ name: 'home', params: { accountId: '1' } });
    await router.push({ name: 'jrc_service_desk_tickets', params: { accountId: '1' } });
    expect(router.currentRoute.value.name).toBe('home');
  });
  it('flag refresh is for the target Account, not the previous URL', async () => {
    state.account = { id: '2', features: { jrc_service_desk: true } };
    const router = makeRouter();
    await router.push({ name: 'home', params: { accountId: '1' } });
    await router.push({ name: 'jrc_service_desk_overview', params: { accountId: '2' } });
    expect(get.mock.calls.every(call => call[0] === '/api/v1/accounts/2')).toBe(true);
    expect(router.currentRoute.value.name).toBe('jrc_service_desk_overview');
  });
  it('a wrong-account response never enters the module', async () => {
    state.account = { id: '2', features: { jrc_service_desk: true } };
    const router = makeRouter();
    await router.push({ name: 'home', params: { accountId: '1' } });
    await router.push({ name: 'jrc_service_desk_overview', params: { accountId: '1' } });
    expect(router.currentRoute.value.name).toBe('home');
  });
  it('transport failure cannot fall back to a cached enabled feature', async () => {
    state.account.features.jrc_service_desk = true;
    get.mockRejectedValue(new Error('offline'));
    const router = makeRouter();
    await router.push({ name: 'home', params: { accountId: '1' } });
    await router.push({ name: 'jrc_service_desk_overview', params: { accountId: '1' } });
    expect(router.currentRoute.value.name).toBe('home');
  });
  it('revoking the flag prevents navigation between module screens', async () => {
    state.account.features.jrc_service_desk = true;
    const router = makeRouter();
    await router.push({ name: 'jrc_service_desk_overview', params: { accountId: '1' } });
    state.account.features.jrc_service_desk = false;
    await router.push({ name: 'jrc_service_desk_tickets', params: { accountId: '1' } });
    expect(router.currentRoute.value.name).toBe('home');
  });
});
