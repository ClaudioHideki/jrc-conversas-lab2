import { routes as jrcFlowRoutes } from './jrcFlows/routes';
import settings from './settings/settings.routes';
import conversation from './conversation/conversation.routes';
import { routes as searchRoutes } from '../../modules/search/search.routes';
import { routes as callRoutes } from './calls/routes';
import { routes as contactRoutes } from './contacts/routes';
import { routes as companyRoutes } from './companies/routes';
import { routes as notificationRoutes } from './notifications/routes';
import { routes as inboxRoutes } from './inbox/routes';
import { frontendURL } from '../../helper/URLHelper';
import helpcenterRoutes from './helpcenter/helpcenter.routes';
import campaignsRoutes from './campaigns/campaigns.routes';
import { routes as captainRoutes } from './captain/captain.routes';
import { routes as webphoneRoutes } from './webphone/routes';
import { routes as videoConferenceRoutes } from './videoConference/routes';
import { routes as whatsappCallingRoutes } from './whatsappCalling/routes';
import { routes as salesRoutes } from './sales/routes';
import crmRoutes from './crm/crm.routes';
import { routes as jrcCampaignRoutes } from './jrcCampaigns/routes';
import { routes as jrcCopilotRoutes } from './jrcCopilot/routes';
import { routes as jrcServiceRoutes } from './jrcService/routes';
import { routes as jrcAiRoutes } from './jrcAI/routes';
import { routes as jrcBrokerRoutes } from './jrcBroker/routes';
import { routes as serviceDeskRoutes } from './serviceDesk/routes';
import { routes as jrcProjectRoutes } from './jrcProjects/routes';
import { routes as operationsRoutes } from './jrcOperations/routes';
import AppContainer from './Dashboard.vue';
import Suspended from './suspended/Index.vue';
import NoAccounts from './noAccounts/Index.vue';
import OnboardingAccountDetails from './onboarding/Index.vue';
import OnboardingInboxSetup from './onboarding/InboxSetup.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId'),
      component: AppContainer,
      children: [
        ...captainRoutes,
        ...inboxRoutes,
        ...conversation.routes,
        ...settings.routes,
        ...callRoutes,
        ...contactRoutes,
        ...companyRoutes,
        ...searchRoutes,
        ...notificationRoutes,
        ...helpcenterRoutes.routes,
        ...campaignsRoutes.routes,
        ...webphoneRoutes,
        ...videoConferenceRoutes,
        ...whatsappCallingRoutes,
        ...salesRoutes,
        ...crmRoutes.routes,
        ...jrcCampaignRoutes,
        ...jrcCopilotRoutes,
        ...jrcServiceRoutes,
        ...jrcAiRoutes,
        ...jrcBrokerRoutes,
        ...jrcFlowRoutes,
        ...serviceDeskRoutes,
        ...jrcProjectRoutes,
        ...operationsRoutes,
      ],
    },
    {
      path: frontendURL('accounts/:accountId/onboarding'),
      name: 'onboarding_account_details',
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
      component: OnboardingAccountDetails,
    },
    {
      path: frontendURL('accounts/:accountId/onboarding/inbox-setup'),
      name: 'onboarding_inbox_setup',
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
      component: OnboardingInboxSetup,
    },
    {
      path: frontendURL('accounts/:accountId/suspended'),
      name: 'account_suspended',
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
      component: Suspended,
    },
    {
      path: frontendURL('no-accounts'),
      name: 'no_accounts',
      component: NoAccounts,
    },
  ],
};
