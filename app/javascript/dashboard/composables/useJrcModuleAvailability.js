import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter } from './store';
import { usePolicy } from './usePolicy';
import { useAgenda } from 'dashboard/routes/dashboard/jrcOperations/useAgenda';
import { useServiceDeskNavigation } from './useServiceDeskNavigation';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import NicoAPI from 'dashboard/api/jrcNico';
import VideoConferenceSettingsAPI from 'dashboard/api/videoConferenceSettings';
import { hasVideoConferenceUrls } from 'dashboard/helper/videoConference';

export function useJrcModuleAvailability() {
  const { t } = useI18n();
  const router = useRouter();
  const policy = usePolicy();
  const flags = useMapGetter('accounts/isFeatureEnabledonAccount');
  const { accountId, userId, status, loading, error, agendaText } = useAgenda();
  const enabled = flag => flags.value(Number(accountId.value), flag) === true;
  const serviceDeskEnabled = computed(() =>
    enabled(FEATURE_FLAGS.JRC_SERVICE_DESK)
  );
  const serviceDesk = useServiceDeskNavigation(
    accountId,
    userId,
    serviceDeskEnabled
  );
  const nicoStatus = ref('LOADING');
  const videoStatus = ref('LOADING');
  watch(
    [accountId, userId],
    async ([id], _, onCleanup) => {
      const controller = new AbortController();
      onCleanup(() => controller.abort());
      nicoStatus.value = 'LOADING';
      videoStatus.value = 'LOADING';
      const [nico, video] = await Promise.allSettled([
        NicoAPI.agents(id, controller.signal),
        VideoConferenceSettingsAPI.getMine(),
      ]);
      if (controller.signal.aborted) return;
      if (nico.status === 'fulfilled')
        nicoStatus.value = nico.value.data.some(agent => agent.key === 'nico')
          ? 'ENABLED'
          : 'DISABLED_GENERIC';
      else nicoStatus.value = 'UNAVAILABLE';
      if (video.status === 'fulfilled')
        videoStatus.value = hasVideoConferenceUrls(video.value.data)
          ? 'CONFIGURED'
          : 'NOT_CONFIGURED';
      else videoStatus.value = 'UNAVAILABLE';
    },
    { immediate: true }
  );
  const operationState = allowed => {
    if (loading.value || (!status.value && !error.value)) return 'LOADING';
    if (error.value) return 'UNAVAILABLE';
    return allowed ? 'ENABLED' : 'DISABLED_GENERIC';
  };
  const module = (key, label, icon, tone, state, routeName, command) => {
    const destination = {
      name: routeName,
      params: { accountId: accountId.value },
    };
    let available = ['ENABLED', 'CONFIGURED'].includes(state);
    if (available && routeName) {
      const meta = router.hasRoute(routeName)
        ? router.resolve(destination).meta
        : null;
      available = !!meta && policy.checkPermissions(meta.permissions);
      if (!available) state = 'UNAVAILABLE';
    }
    return {
      key,
      label,
      icon,
      tone,
      status: state,
      route: available && routeName ? destination : null,
      command: available ? command : null,
      available,
    };
  };
  const featureState = flag => (enabled(flag) ? 'ENABLED' : 'DISABLED_GENERIC');
  const serviceDeskState = computed(() => {
    if (!serviceDeskEnabled.value) return 'DISABLED_GENERIC';
    if (serviceDesk.visible) return 'ENABLED';
    if (serviceDesk.status === 'loading') return 'LOADING';
    return 'UNAVAILABLE';
  });
  const modules = computed(() => [
    module(
      'contacts',
      t('SIDEBAR.CONTACTS'),
      'i-lucide-contact-round',
      'blue',
      'ENABLED',
      'contacts_dashboard_index'
    ),
    module(
      'companies',
      t('SIDEBAR.COMPANIES'),
      'i-lucide-building-2',
      'violet',
      enabled(FEATURE_FLAGS.JRC_CUSTOMER_MASTER) ||
        enabled(FEATURE_FLAGS.COMPANIES)
        ? 'ENABLED'
        : 'DISABLED_GENERIC',
      enabled(FEATURE_FLAGS.JRC_CUSTOMER_MASTER)
        ? 'jrc_customer_companies'
        : 'companies_dashboard_index'
    ),
    module(
      'crm',
      t('INBOX.OVERVIEW.CHANNELS.CRM'),
      'i-lucide-target',
      'blue',
      operationState(status.value?.crm_enabled),
      'crm_dashboard'
    ),
    module(
      'relationship',
      t('RELATIONSHIP.TITLE'),
      'i-lucide-heart-handshake',
      'ruby',
      enabled(FEATURE_FLAGS.JRC_CUSTOMER_MASTER) &&
        enabled(FEATURE_FLAGS.JRC_RELATIONSHIP)
        ? 'ENABLED'
        : 'DISABLED_GENERIC',
      'jrc_relationship_overview'
    ),
    module(
      'service_desk',
      t('JRC_SERVICE_DESK.MODULE'),
      'i-lucide-headset',
      'amber',
      serviceDeskState.value,
      serviceDesk.route
    ),
    module(
      'projects',
      agendaText('PROJECTS'),
      'i-lucide-folder-kanban',
      'teal',
      operationState(status.value?.projects_enabled),
      'jrc_projects_list'
    ),
    module(
      'agenda',
      agendaText('MY_AGENDA'),
      'i-lucide-calendar-days',
      'violet',
      operationState(
        status.value?.projects_enabled || status.value?.crm_enabled
      ),
      'jrc_operations_agenda'
    ),
    module(
      'campaigns',
      t('SIDEBAR.CAMPAIGNS'),
      'i-lucide-send',
      'ruby',
      featureState(FEATURE_FLAGS.JRC_CAMPAIGNS),
      'jrc_campaigns_index'
    ),
    module(
      'nico',
      'NICO',
      'i-lucide-sparkles',
      'violet',
      nicoStatus.value,
      null,
      'nico'
    ),
    module(
      'video_conference',
      t('INBOX.OVERVIEW.CHANNELS.VIDEO_CONFERENCE'),
      'i-lucide-video',
      'blue',
      videoStatus.value,
      'video_conference_index'
    ),
    module(
      'flows',
      'Flows',
      'i-lucide-workflow',
      'blue',
      window.chatwootConfig?.jrcFlowsEnabled === true && enabled('jrc_flows')
        ? 'ENABLED'
        : 'DISABLED_GENERIC',
      'jrc_flows'
    ),
    module(
      'broker',
      'Broker',
      'i-lucide-qr-code',
      'teal',
      window.chatwootConfig?.jrcBrokerEnabled === true && enabled('jrc_broker')
        ? 'ENABLED'
        : 'DISABLED_GENERIC',
      'jrc_broker_connections'
    ),
    module(
      'reports',
      t('SIDEBAR.REPORTS'),
      'i-lucide-chart-no-axes-combined',
      'blue',
      featureState(FEATURE_FLAGS.REPORTS),
      policy.checkPermissions(['administrator', 'report_manage'])
        ? 'account_overview_reports'
        : 'my_performance'
    ),
  ]);
  const statusLabel = state => {
    if (state === 'LOADING') return t('JRC_HOME.LOADING');
    if (state === 'UNAVAILABLE') return t('JRC_HOME.UNAVAILABLE');
    return t(`INBOX.OVERVIEW.CHANNEL_STATUS.${state}`);
  };
  return { modules, statusLabel };
}
