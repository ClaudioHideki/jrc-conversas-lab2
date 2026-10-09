/* global axios */
import { frontendURL } from 'dashboard/helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import store from 'dashboard/store';
import types from 'dashboard/store/mutation-types';
import { SERVICE_DESK_ROUTES, serviceDeskRouteName } from './routeDefinitions.js';
import { canonicalId } from './helpers/access.js';
import { createIntegratedGuard } from './helpers/nativeIntegration.js';
import ServiceDeskAPI from 'dashboard/api/serviceDesk';
import StructureAPI from 'dashboard/api/serviceDeskStructure';
import { structureContext } from './helpers/structure.js';
const pages = {
  overview: () => import('./views/OverviewView.vue'),
  tickets: () => import('./views/TicketListView.vue'),
  detail: () => import('./views/TicketDetailView.vue'),
  form: () => import('./views/TicketFormView.vue'),
  catalog: () => import('./views/CatalogView.vue'),
  serviceCatalog: () => import('./views/ServiceCatalogView.vue'),
  knowledge: () => import('./views/KnowledgeView.vue'),
  board: () => import('./views/OperationsBoardView.vue'),
  resources: () => import('./views/ResourcesView.vue'),
  reports: () => import('./views/ReportsView.vue'),
  sla: () => import('./views/SlaView.vue'),
  planned: () => import('./views/PlannedView.vue'),
  settings: () => import('./views/SettingsView.vue'),
  automations: () => import('./views/AutomationsView.vue'),
  nativeSurveys: () => import('./views/NativeSurveysView.vue'),
};
const meta = { featureFlag: FEATURE_FLAGS.JRC_SERVICE_DESK, permissions: ['administrator', 'agent', 'custom_role'] };
const guard = createIntegratedGuard(store, async accountId => {
  const response = await axios.get(`/api/v1/accounts/${accountId}`, { timeout: 15000 });
  if (canonicalId(response.data?.id) !== accountId || !response.data.features || typeof response.data.features !== 'object' || Array.isArray(response.data.features))
    throw new Error('Account mismatch');
  store.commit(`accounts/${types.ADD_ACCOUNT}`, response.data);
  return response.data;
}, accountId => ServiceDeskAPI.context(accountId));
let structuralGuardGeneration = 0;
const structuralGuard = async to => {
  const generation = ++structuralGuardGeneration;
  const accountId = canonicalId(to.params.accountId), userId = canonicalId(store.getters.getCurrentUserID);
  if (!accountId || !userId) return false;
  try {
    const response = await axios.get(`/api/v1/accounts/${accountId}`, { timeout: 15000 });
    if (generation !== structuralGuardGeneration || canonicalId(store.getters.getCurrentUserID) !== userId) return false;
    if (canonicalId(response.data?.id) !== accountId || response.data?.features?.jrc_service_desk !== true) throw new Error('Feature unavailable');
    store.commit(`accounts/${types.ADD_ACCOUNT}`, response.data);
    const payload = await StructureAPI.context(accountId);
    if (generation !== structuralGuardGeneration || canonicalId(store.getters.getCurrentUserID) !== userId) return false;
    structureContext(payload, { accountId, userId });
    return true;
  } catch {
    if (generation !== structuralGuardGeneration || canonicalId(store.getters.getCurrentUserID) !== userId) return false;
    return { name: 'jrc_service_desk_denied', params: { accountId }, query: { reason: 'denied' } };
  }
};
export const routes = [{
    path: frontendURL('accounts/:accountId/service-desk-structure'),
    name: 'jrc_service_desk_structure',
    component: () => import('./views/StructureView.vue'),
    meta,
    beforeEnter: structuralGuard,
  }, {
    path: frontendURL('accounts/:accountId/service-desk'),
    component: () => import('./ServiceDeskLayout.vue'),
    meta,
    beforeEnter: guard,
    children: SERVICE_DESK_ROUTES.map(definition => ({
      path: definition.path,
      name: serviceDeskRouteName(definition.key),
      component: pages[definition.page],
      meta: { ...meta, serviceDeskScreen: definition.key },
      props: { screen: definition.key, resource: definition.resource || '' },
      beforeEnter: guard,
    })),
  }, {
    path: frontendURL('accounts/:accountId/service-desk-access'),
    name: 'jrc_service_desk_denied',
    component: () => import('./views/AccessStateView.vue'),
    meta,
    children: [],
  }];
