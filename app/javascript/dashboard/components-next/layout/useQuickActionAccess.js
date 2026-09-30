import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { useServiceDeskNavigation } from 'dashboard/composables/useServiceDeskNavigation';
import { screenAccessible } from 'dashboard/routes/dashboard/serviceDesk/helpers/nativeIntegration';
import {
  SERVICE_DESK_ROUTES,
  serviceDeskRouteName,
} from 'dashboard/routes/dashboard/serviceDesk/routeDefinitions';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

export function useQuickActionContext() {
  const store = useStore();
  const route = useRoute();
  const router = useRouter();
  const policy = usePolicy();
  const accountId = computed(() => Number(route.params.accountId));
  const userId = computed(() => store.getters.getCurrentUserID);
  const user = computed(() => store.getters.getCurrentUser);
  const account = computed(() =>
    user.value?.accounts?.find(item => Number(item.id) === accountId.value)
  );
  const destination = (name, query) => ({
    name,
    params: { accountId: accountId.value },
    ...(query ? { query } : {}),
  });
  const routeAllowed = name => {
    if (!account.value || !router.hasRoute(name)) return false;
    const { meta } = router.resolve(destination(name));
    return policy.shouldShow(
      meta.featureFlag,
      meta.permissions,
      meta.installationTypes
    );
  };
  const crmAllowed = computed(
    () =>
      policy.isFeatureFlagEnabled(FEATURE_FLAGS.JRC_CRM) &&
      account.value?.permissions?.includes('jrc_crm') &&
      routeAllowed('crm_leads')
  );
  return {
    accountId,
    userId,
    user,
    account,
    crmAllowed,
    destination,
    routeAllowed,
    policy,
  };
}

export function useQuickActionAccess() {
  const context = useQuickActionContext();
  const {
    accountId,
    userId,
    account,
    crmAllowed,
    destination,
    routeAllowed,
    policy,
  } = context;
  const router = useRouter();
  const serviceDeskEnabled = computed(
    () =>
      !!account.value &&
      policy.isFeatureFlagEnabled(FEATURE_FLAGS.JRC_SERVICE_DESK)
  );
  const serviceDesk = useServiceDeskNavigation(
    accountId,
    userId,
    serviceDeskEnabled
  );
  const actions = computed(() => [
    ...(routeAllowed('contacts_dashboard_index')
      ? [
          {
            key: 'CONTACT',
            icon: 'i-lucide-user-round-plus',
            tone: 'blue',
            command: 'contact',
          },
        ]
      : []),
    ...(routeAllowed('ramal_index')
      ? [
          {
            key: 'CALL',
            icon: 'i-lucide-phone-call',
            tone: 'teal',
            to: destination('ramal_index'),
          },
        ]
      : []),
    ...(crmAllowed.value
      ? [
          {
            key: 'LEAD',
            icon: 'i-lucide-chart-no-axes-combined',
            tone: 'violet',
            to: destination('crm_leads', { new: '1' }),
          },
          {
            key: 'DEAL',
            icon: 'i-lucide-target',
            tone: 'violet',
            to: destination('crm_deals', { new: '1' }),
          },
          {
            key: 'ACTIVITY',
            icon: 'i-lucide-calendar-plus',
            tone: 'blue',
            to: destination('crm_activities', { new: '1' }),
          },
        ].filter(action => routeAllowed(action.to.name))
      : []),
    ...(serviceDeskEnabled.value &&
    serviceDesk.visible &&
    screenAccessible(
      serviceDesk.context,
      SERVICE_DESK_ROUTES.find(item => item.key === 'new')
    ) &&
    router.hasRoute(serviceDeskRouteName('new'))
      ? [
          {
            key: 'TICKET',
            icon: 'i-lucide-ticket-plus',
            tone: 'amber',
            to: destination(serviceDeskRouteName('new')),
          },
        ]
      : []),
    { key: 'NICO', icon: 'i-lucide-sparkles', tone: 'violet', command: 'nico' },
  ]);
  return { ...context, actions };
}
