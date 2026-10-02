import { h } from 'vue';
import CustomerPageBoundary from './CustomerPageBoundary.vue';
import { frontendURL } from '../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../featureFlags';
import CompaniesPage from './CompaniesPage.vue';
import CompanyPage from './CompanyPage.vue';
import TaxonomyPage from './TaxonomyPage.vue';
import ImportsPage from './ImportsPage.vue';
const scoped = page => ({ render: () => h(CustomerPageBoundary, { page }) });
const meta = {
  featureFlag: FEATURE_FLAGS.JRC_CUSTOMER_MASTER,
  permissions: ['administrator', 'agent', 'contact_manage'],
};
export const routes = [
  {
    path: frontendURL('accounts/:accountId/customers/companies'),
    name: 'jrc_customer_companies',
    component: scoped(CompaniesPage),
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/customers/companies/:companyId'),
    name: 'jrc_customer_company',
    component: scoped(CompanyPage),
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/customers/segments'),
    name: 'jrc_customer_segments',
    component: scoped(TaxonomyPage),
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/customers/groups'),
    name: 'jrc_customer_groups',
    component: scoped(TaxonomyPage),
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/customers/imports'),
    name: 'jrc_customer_imports',
    component: scoped(ImportsPage),
    meta: { ...meta, permissions: ['administrator'] },
  },
];
