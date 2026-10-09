import { frontendURL } from 'dashboard/helper/URLHelper';
import api from 'dashboard/api/jrcNicoHelpdesk';

export const helpdeskGuard = async to => {
  const accountId = Number(to.params.accountId);
  if (!Number.isSafeInteger(accountId) || accountId <= 0) return false;
  try {
    const response = await api.show(accountId);
    if (Number(response.data.account_id) === accountId) return true;
    return { name: 'jrc_service_desk_denied', params: { accountId } };
  } catch {
    return { name: 'jrc_service_desk_denied', params: { accountId } };
  }
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/nico-helpdesk'),
    name: 'jrc_nico_helpdesk',
    component: () => import('./HelpdeskPage.vue'),
    meta: { permissions: ['administrator', 'agent', 'custom_role'] },
    beforeEnter: helpdeskGuard,
  },
];
